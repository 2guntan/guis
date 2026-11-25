// Page « Utilisateurs » : désactiver, réactiver, supprimer (ticket #29, spec #24).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

const ADMIN = { phone: '221770000060', name: 'Admin Test', role: 'admin', password: 'admin-pass-123' };

async function cookieOf(u) {
  const r = await fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone: u.phone, password: u.password, suite: '/' }) });
  return (r.headers.get('set-cookie') ?? '').split(';')[0];
}
const call = async (cookie, method, p, body) => {
  const res = await fetch(BASE + p, { method, headers: { cookie, ...(body ? { 'content-type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, data: await res.json().catch(() => null) };
};
async function admin() {
  const u = await createUser(ADMIN);
  return { ...u, cookie: await cookieOf(ADMIN) };
}
const setActive = (a, id, active) => call(a.cookie, 'PUT', `/api/users/${id}/activation`, { active });

test('désactiver : connexion refusée, sessions fermées, attributions retirées, historique conservé', async () => {
  const a = await admin();
  const agent = await createUser({ phone: '221770000061', name: 'Mansour Ba', role: 'agent', password: '4827' });
  await db.query(`insert into communes (name) values ('NOTTO')`);
  await db.query(`insert into agent_communes (user_id, commune) values ($1, 'NOTTO')`, [agent.id]);
  const pid = randomUUID();
  await db.query(`insert into producers (id, last_name, first_name, commune, source, consent_at, created_by, consent_by) values ($1, 'KA', 'Awa', 'NOTTO', 'app', now(), $2, $2)`, [pid, agent.id]);
  const token = await login(agent);

  assert.equal((await setActive(a, agent.id, false)).status, 200);
  assert.equal((await api('GET', '/api/app/bootstrap', { token })).status, 401, 'session fermée');
  assert.equal((await api('POST', '/api/auth/login', { body: { phone: agent.phone, password: agent.password } })).status, 401, 'connexion refusée');
  assert.equal((await db.query('select count(*)::int as n from agent_communes')).rows[0].n, 0);
  assert.equal((await db.query('select created_by from producers where id = $1', [pid])).rows[0].created_by, agent.id, 'historique conservé');
  const html = await (await fetch(`${BASE}/producteurs`, { headers: { cookie: a.cookie } })).text();
  assert.match(html, /Mansour Ba/, 'son nom reste affiché sur ce qu’il a fait');
  const list = (await call(a.cookie, 'GET', '/api/users')).data.users;
  assert.equal(list.find((u) => u.id === agent.id).active, false);
});

test('réactiver : la connexion redevient possible avec le secret actuel, sans les attributions', async () => {
  const a = await admin();
  const agent = await createUser({ phone: '221770000062', role: 'agent', password: '4827' });
  await db.query(`insert into communes (name) values ('NOTTO')`);
  await db.query(`insert into agent_communes (user_id, commune) values ($1, 'NOTTO')`, [agent.id]);
  await setActive(a, agent.id, false);
  assert.equal((await setActive(a, agent.id, true)).status, 200);
  assert.ok(await login(agent));
  assert.equal((await db.query('select count(*)::int as n from agent_communes')).rows[0].n, 0);
  const ev = (await db.query('select action from account_events where target_id = $1 order by id', [agent.id])).rows.map((r) => r.action);
  assert.deepEqual(ev, ['deactivate', 'reactivate']);
});

test('supprimer : accepté pour un compte sans référence, 409 sinon ; la liste dit s’il est supprimable', async () => {
  const a = await admin();
  const fresh = await createUser({ phone: '221770000063', name: 'Erreur de saisie', role: 'agent', password: '4827' });
  const worker = await createUser({ phone: '221770000064', role: 'agent', password: '4827' });
  await db.query(`insert into producers (id, last_name, first_name, source, consent_at, created_by) values ($1, 'KA', 'Awa', 'app', now(), $2)`, [randomUUID(), worker.id]);
  const list = (await call(a.cookie, 'GET', '/api/users')).data.users;
  assert.equal(list.find((u) => u.id === fresh.id).deletable, true);
  assert.equal(list.find((u) => u.id === worker.id).deletable, false);
  const refused = await call(a.cookie, 'DELETE', `/api/users/${worker.id}`);
  assert.equal(refused.status, 409);
  assert.equal(refused.data.error, 'Ce compte a déjà travaillé : désactivez-le.');
  assert.equal((await call(a.cookie, 'DELETE', `/api/users/${fresh.id}`)).status, 200);
  assert.equal((await db.query('select count(*)::int as n from users where id = $1', [fresh.id])).rows[0].n, 0);
  const ev = (await db.query(`select action, detail from account_events where action = 'delete'`)).rows;
  assert.deepEqual(ev, [{ action: 'delete', detail: 'Erreur de saisie' }]);
});

test('garde-fous : pas d’auto-désactivation ni d’auto-suppression ; un autre admin peut être désactivé', async () => {
  const a = await admin();
  const self = await setActive(a, a.id, false);
  assert.equal(self.status, 409);
  assert.equal(self.data.error, 'Vous ne pouvez pas désactiver votre propre compte.');
  assert.equal((await call(a.cookie, 'DELETE', `/api/users/${a.id}`)).status, 409);
  const other = await createUser({ phone: '221770000065', name: 'Autre Admin', role: 'admin', password: 'admin-pass-456' });
  assert.equal((await setActive(a, other.id, false)).status, 200, 'il reste l’admin connecté');
  assert.equal((await db.query(`select count(*)::int as n from users where role = 'admin' and active`)).rows[0].n, 1);
});

test('réservé à l’admin', async () => {
  const coord = await createUser({ phone: '221770000067', role: 'coordinator', password: 'coord-pass-123' });
  const agent = await createUser({ phone: '221770000068', role: 'agent', password: '4827' });
  const c = await cookieOf(coord);
  assert.equal((await call(c, 'PUT', `/api/users/${agent.id}/activation`, { active: false })).status, 403);
  assert.equal((await call(c, 'DELETE', `/api/users/${agent.id}`)).status, 403);
});

test('la page propose « Désactiver » et « Supprimer » selon le compte', async () => {
  const a = await admin();
  await createUser({ phone: '221770000069', name: 'Nouveau', role: 'agent', password: '4827' });
  const html = await (await fetch(`${BASE}/utilisateurs`, { headers: { cookie: a.cookie } })).text();
  assert.match(html, /Désactiver/);
  assert.match(html, /Supprimer/);
});
