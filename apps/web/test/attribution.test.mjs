// Attribution des communes aux agents et synchronisation limitée (ticket 11, ADR-0001).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, login, resetDb } from './helpers.mjs';

const scripts = path.resolve(import.meta.dirname, '../scripts');
const dir = mkdtempSync(path.join(tmpdir(), 'guis-attr-'));

function load(text) {
  const f = path.join(dir, `${randomUUID()}.csv`);
  writeFileSync(f, text);
  const r = spawnSync('node', [path.join(scripts, 'load-attribution.mjs'), f], { env: process.env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}

async function producer(commune, last = 'P', extra = {}) {
  const id = randomUUID();
  await db.query(
    `insert into producers (id, last_name, first_name, phone, commune, source, created_by) values ($1, $2, 'X', $3, $4, 'import', $5)`,
    [id, last, extra.phone ?? null, commune, extra.created_by ?? null],
  );
  return id;
}

const bootstrap = async (token) => (await api('GET', '/api/app/bootstrap', { token })).data;
const lastNames = (data) => data.producers.map((p) => p.last_name).sort();

let a1, a2, admin;
beforeEach(async () => {
  await resetDb();
  await db.query(`insert into communes (name) values ('COMMUNE A'), ('COMMUNE B'), ('COMMUNE C')`);
  a1 = await createUser({ phone: '221770000091', name: 'Agent Un' });
  a2 = await createUser({ phone: '221770000092', name: 'Agent Deux' });
  admin = await createUser({ phone: '221770000099', name: 'Admin', role: 'admin' });
  const pa = await producer('COMMUNE A', 'A1');
  await producer('COMMUNE A', 'A2');
  const pb = await producer('COMMUNE B', 'B1');
  await producer('COMMUNE C', 'C1');
  await db.query(`insert into fields (id, producer_id, name) values ($1, $2, 'champ A'), ($3, $4, 'champ B')`, [randomUUID(), pa, randomUUID(), pb]);
  await db.query(`insert into seed_distributions (id, producer_id, variety, quantity_kg) values ($1, $2, 'Spunta', 10)`, [randomUUID(), pb]);
});
after(() => db.end());

test('chargement : deux agents sur une commune, un agent sur deux communes, compte créé', async () => {
  const r = load('commune;nom_agent;telephone_agent\nCommune A;Agent Un;77 000 00 91\nCOMMUNE A;Agent Deux;770000092\nCOMMUNE B;Agent Deux;77 000 00 92\nCOMMUNE C;Agent Trois;77 000 00 93\nCOMMUNE D;;\n');
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Attribution chargée : 4 ligne\(s\), 3 agent\(s\), 1 compte\(s\) créé\(s\)/);
  assert.match(r.out, /COMMUNE A : 2 agent\(s\), 2 producteur\(s\)/);
  assert.match(r.out, /ligne 6 : COMMUNE D sans agent, ignorée/);
  assert.match(r.out, /221770000093 Agent Trois : \d{4}\b/);
  const { rows } = await db.query(
    `select u.phone, string_agg(a.commune, ',' order by a.commune) as communes from agent_communes a join users u on u.id = a.user_id group by u.phone order by u.phone`,
  );
  assert.deepEqual(rows, [
    { phone: '221770000091', communes: 'COMMUNE A' },
    { phone: '221770000092', communes: 'COMMUNE A,COMMUNE B' },
    { phone: '221770000093', communes: 'COMMUNE C' },
  ]);
  const created = await db.query(`select role, name from users where phone = '221770000093'`);
  assert.deepEqual(created.rows, [{ role: 'agent', name: 'Agent Trois' }]);
});

test('synchronisation : chaque agent ne reçoit que ses communes, l’admin tout', async () => {
  load('commune;telephone\nCOMMUNE A;770000091\nCOMMUNE A;770000092\nCOMMUNE B;770000092\n');
  const d1 = await bootstrap(await login(a1));
  assert.deepEqual(lastNames(d1), ['A1', 'A2']);
  assert.deepEqual(d1.user.communes, ['COMMUNE A']);
  assert.equal(d1.fields.length, 1);
  assert.equal(d1.seeds.length, 0);
  const d2 = await bootstrap(await login(a2));
  assert.deepEqual(lastNames(d2), ['A1', 'A2', 'B1']);
  assert.equal(d2.fields.length, 2);
  assert.equal(d2.seeds.length, 1);
  const da = await bootstrap(await login(admin));
  assert.deepEqual(lastNames(da), ['A1', 'A2', 'B1', 'C1']);
  assert.deepEqual(da.user.communes, ['COMMUNE A', 'COMMUNE B', 'COMMUNE C']);
});

test('agent sans commune : seulement ses propres créations, rattachées à rien', async () => {
  const token = await login(a1);
  assert.deepEqual(lastNames(await bootstrap(token)), []);
  const id = randomUUID();
  const r = await api('PUT', `/api/app/producers/${id}`, { token, body: { last_name: 'NOUVEAU', first_name: 'Awa', consent_at: '2026-11-24T10:00:00Z' } });
  assert.equal(r.status, 200);
  assert.deepEqual(lastNames(await bootstrap(token)), ['NOUVEAU']);
  assert.equal((await db.query('select commune from producers where id = $1', [id])).rows[0].commune, null);
});

test('un producteur créé par un agent d’une seule commune y est rattaché', async () => {
  load('commune;telephone\nCOMMUNE B;770000091\n');
  const id = randomUUID();
  await api('PUT', `/api/app/producers/${id}`, { token: await login(a1), body: { last_name: 'NOUVEAU', first_name: 'Awa', consent_at: '2026-11-24T10:00:00Z' } });
  assert.equal((await db.query('select commune from producers where id = $1', [id])).rows[0].commune, 'COMMUNE B');
});

test('modification hors périmètre refusée (403), y compris un champ', async () => {
  load('commune;telephone\nCOMMUNE A;770000091\n');
  const token = await login(a1);
  const b1 = (await db.query(`select id from producers where last_name = 'B1'`)).rows[0].id;
  const p = await api('PUT', `/api/app/producers/${b1}`, { token, body: { last_name: 'B1', first_name: 'X', consent_at: '2026-11-24T10:00:00Z' } });
  assert.equal(p.status, 403);
  assert.match(p.data.error, /pas attribué/);
  const f = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: { producer_id: b1, name: 'intrus' } });
  assert.equal(f.status, 403);
  const a = (await db.query(`select id from producers where last_name = 'A1'`)).rows[0].id;
  assert.equal((await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: { producer_id: a, name: 'ok' } })).status, 200);
  // L'admin peut tout modifier, et se connecte à l'app.
  assert.equal((await api('PUT', `/api/app/producers/${b1}`, { token: await login(admin), body: { last_name: 'B1', first_name: 'Y', consent_at: '2026-11-24T10:00:00Z' } })).status, 200);
});

test('changer l’attribution change ce que reçoit le téléphone', async () => {
  load('commune;telephone\nCOMMUNE A;770000091\n');
  const token = await login(a1);
  assert.deepEqual(lastNames(await bootstrap(token)), ['A1', 'A2']);
  const r = load('commune;telephone\nCOMMUNE C;770000091\n');
  assert.match(r.out, /COMMUNE A : 0 agent\(s\), 2 producteur\(s\) — AUCUN AGENT/);
  assert.deepEqual(lastNames(await bootstrap(token)), ['C1']);
});
