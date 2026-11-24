// Doublon possible signalé à l'admin (ticket 13).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

let agent, token, cookie, existing;
const body = (over = {}) => ({ last_name: 'DIOP', first_name: 'Awa', phone: '77 000 00 11', consent_at: '2026-11-24T10:00:00Z', ...over });

async function adminCookie() {
  await createUser({ phone: '221770000099', role: 'admin', password: 'admin-pass' });
  const r = await fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone: '770000099', password: 'admin-pass', suite: '/' }) });
  return r.headers.get('set-cookie').split(';')[0];
}
const decide = (id, form) =>
  fetch(`${BASE}/api/doublons/${id}`, { method: 'POST', redirect: 'manual', headers: { cookie }, body: new URLSearchParams(form) });
const flag = async (id) => (await db.query('select possible_duplicate_of as d from producers where id = $1', [id])).rows[0]?.d ?? null;

beforeEach(async () => {
  await resetDb();
  agent = await createUser();
  token = await login(agent);
  cookie = await adminCookie();
  existing = randomUUID();
  await db.query(
    `insert into producers (id, last_name, first_name, phone, commune, village, source) values ($1, 'DIOP', 'Awa', '221770000011', 'COMMUNE A', 'VILLAGE UN', 'import')`,
    [existing],
  );
});
after(() => db.end());

test('création dans l’app avec un téléphone connu : doublon possible, visible par l’admin', async () => {
  const id = randomUUID();
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token, body: body() })).status, 200);
  assert.deepEqual(await flag(id), [existing]);
  assert.equal(await flag(existing), null, 'le producteur existant n’est pas marqué');
  const other = randomUUID();
  await api('PUT', `/api/app/producers/${other}`, { token, body: body({ phone: '77 000 00 12' }) });
  assert.equal(await flag(other), null, 'téléphone nouveau : pas de doublon');
  const page = await (await fetch(`${BASE}/doublons`, { headers: { cookie } })).text();
  assert.match(page, /Doublon possible/);
  assert.match(page, /Fusionner dans celui-ci/);
  // L'agent sans commune ne reçoit pas le producteur existant pour autant.
  const { data } = await api('GET', '/api/app/bootstrap', { token });
  assert.deepEqual(data.producers.map((p) => p.id).sort(), [id, other].sort());
});

test('« deux personnes » : le marquage disparaît et ne revient pas', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/producers/${id}`, { token, body: body({ first_name: 'Fatou' }) });
  const r = await decide(id, { action: 'distinct' });
  assert.equal(r.status, 303);
  assert.equal(r.headers.get('location'), '/doublons?fait=distinct');
  assert.equal(await flag(id), null);
  await api('PUT', `/api/app/producers/${id}`, { token, body: body({ first_name: 'Fatou Bintou' }) });
  assert.equal(await flag(id), null, 'couple déjà tranché');
});

test('fusion : champs, remises et photo passent sur l’existant, l’ancien identifiant est redirigé', async () => {
  const id = randomUUID();
  const seed = { id: randomUUID(), variety: 'Spunta', quantity_kg: 50, received_on: '2026-11-20' };
  await api('PUT', `/api/app/producers/${id}`, { token, body: body({ seeds: [seed], village: 'AUTRE' }) });
  const field = randomUUID();
  assert.equal((await api('PUT', `/api/app/fields/${field}`, { token, body: { producer_id: id, name: 'Champ 1' } })).status, 200);
  const r = await decide(id, { action: 'merge', into: existing });
  assert.equal(r.headers.get('location'), '/doublons?fait=merge');
  assert.equal((await db.query('select 1 from producers where id = $1', [id])).rowCount, 0);
  assert.equal((await db.query('select producer_id from fields where id = $1', [field])).rows[0].producer_id, existing);
  assert.equal((await db.query('select producer_id from seed_distributions where id = $1', [seed.id])).rows[0].producer_id, existing);
  const kept = (await db.query('select village, consent_at, consent_by from producers where id = $1', [existing])).rows[0];
  assert.equal(kept.village, 'VILLAGE UN', 'les données de l’existant sont gardées');
  assert.ok(kept.consent_at, 'le consentement recueilli sur le terrain est repris');
  assert.equal(kept.consent_by, agent.id);
  // Un envoi en retard du téléphone ne recrée pas le producteur fusionné ; un champ suit le producteur gardé.
  const late = await api('PUT', `/api/app/producers/${id}`, { token, body: body() });
  assert.equal(late.status, 200);
  assert.equal(late.data.merged_into, existing);
  assert.equal((await db.query('select 1 from producers where id = $1', [id])).rowCount, 0);
  await api('PUT', `/api/app/fields/${randomUUID()}`, { token: await login(await createUser({ phone: '221770000098', role: 'admin', password: 'motdepasse' })), body: { producer_id: id, name: 'Champ 2' } });
  assert.equal((await db.query(`select producer_id from fields where name = 'Champ 2'`)).rows[0].producer_id, existing);
});

test('fusion refusée vers un producteur qui n’est pas un candidat, et réservée à l’admin', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/producers/${id}`, { token, body: body() });
  const stranger = randomUUID();
  await db.query(`insert into producers (id, last_name, first_name, source) values ($1, 'X', 'Y', 'import')`, [stranger]);
  assert.equal((await decide(id, { action: 'merge', into: stranger })).headers.get('location'), '/doublons?erreur=1');
  assert.deepEqual(await flag(id), [existing]);
  const agentCookie = `guis_session=${token}`;
  const r = await fetch(`${BASE}/api/doublons/${id}`, { method: 'POST', redirect: 'manual', headers: { cookie: agentCookie }, body: new URLSearchParams({ action: 'distinct' }) });
  assert.equal(r.headers.get('location'), '/login?refus=1');
  assert.deepEqual(await flag(id), [existing]);
});
