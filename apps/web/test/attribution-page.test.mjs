// Page « Attribution » : grille communes × agents et code des agents (ticket #30, spec #24).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

const COORD = { phone: '221770000070', name: 'Coord Test', role: 'coordinator', password: 'coord-pass-123' };
const ADMIN = { phone: '221770000071', name: 'Admin Test', role: 'admin', password: 'admin-pass-123' };

async function cookieOf(u) {
  const r = await fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone: u.phone, password: u.password, suite: '/' }) });
  return (r.headers.get('set-cookie') ?? '').split(';')[0];
}
const call = async (cookie, method, p, body) => {
  const res = await fetch(BASE + p, { method, headers: { cookie, ...(body ? { 'content-type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, data: await res.json().catch(() => null) };
};
async function producer(commune) {
  await db.query(`insert into communes (name) values ($1) on conflict do nothing`, [commune]);
  await db.query(`insert into producers (id, last_name, first_name, commune, source) values ($1, 'BA', 'X', $2, 'import')`, [randomUUID(), commune]);
}
const bootstrapCount = async (token) => (await api('GET', '/api/app/bootstrap', { token })).data.producers.length;

test('grille : communes avec nombre de producteurs, agents actifs avec dernière synchro, cases cochées', async () => {
  await createUser(COORD);
  const c = await cookieOf(COORD);
  const agent = await createUser({ phone: '221770000072', name: 'Mansour Ba', role: 'agent', password: '4827' });
  await createUser({ phone: '221770000073', name: 'Ancien', role: 'agent', password: '4827' });
  await db.query(`update users set active = false where phone = '221770000073'`);
  await producer('NOTTO');
  await producer('NOTTO');
  await producer('THIEPPE');
  await db.query(`insert into agent_communes (user_id, commune) values ($1, 'NOTTO')`, [agent.id]);
  await api('GET', '/api/app/bootstrap', { token: await login(agent) });
  const r = await call(c, 'GET', '/api/attribution');
  assert.equal(r.status, 200);
  assert.deepEqual(r.data.communes, [
    { name: 'NOTTO', producers: 2, agents: [agent.id] },
    { name: 'THIEPPE', producers: 1, agents: [] },
  ]);
  assert.deepEqual(r.data.agents.map((a) => a.name), ['Mansour Ba'], 'seuls les agents actifs');
  assert.ok(r.data.agents[0].last_sync_at);
});

test('cocher et décocher change ce que reçoit l’agent à sa synchronisation suivante', async () => {
  await createUser(COORD);
  const c = await cookieOf(COORD);
  const agent = await createUser({ phone: '221770000074', role: 'agent', password: '4827' });
  await producer('NOTTO');
  await producer('THIEPPE');
  const token = await login(agent);
  assert.equal(await bootstrapCount(token), 0);
  assert.equal((await call(c, 'PUT', '/api/attribution', { commune: 'THIEPPE', user_id: agent.id, assigned: true })).status, 200);
  assert.equal(await bootstrapCount(token), 1);
  await call(c, 'PUT', '/api/attribution', { commune: 'NOTTO', user_id: agent.id, assigned: true });
  assert.equal(await bootstrapCount(token), 2);
  await call(c, 'PUT', '/api/attribution', { commune: 'THIEPPE', user_id: agent.id, assigned: false });
  assert.equal(await bootstrapCount(token), 1);
  assert.equal((await call(c, 'PUT', '/api/attribution', { commune: 'THIEPPE', user_id: agent.id, assigned: false })).status, 200, 'idempotent');
});

test('une commune peut avoir plusieurs agents, un agent plusieurs communes', async () => {
  const a = await createUser(ADMIN);
  const cookie = await cookieOf(ADMIN);
  const x = await createUser({ phone: '221770000075', role: 'agent', password: '4827' });
  const y = await createUser({ phone: '221770000076', role: 'agent', password: '4827' });
  await producer('NOTTO');
  await producer('MBORO');
  for (const [commune, u] of [['NOTTO', x], ['NOTTO', y], ['MBORO', x]]) await call(cookie, 'PUT', '/api/attribution', { commune, user_id: u.id, assigned: true });
  const g = (await call(cookie, 'GET', '/api/attribution')).data;
  assert.equal(g.communes.find((c) => c.name === 'NOTTO').agents.length, 2);
  assert.equal(g.communes.find((c) => c.name === 'MBORO').agents.length, 1);
  assert.ok(a.id);
});

test('cocher pour un compte qui n’est pas un agent actif : 409', async () => {
  const coord = await createUser(COORD);
  const c = await cookieOf(COORD);
  await producer('NOTTO');
  assert.equal((await call(c, 'PUT', '/api/attribution', { commune: 'NOTTO', user_id: coord.id, assigned: true })).status, 409);
  const off = await createUser({ phone: '221770000077', role: 'agent', password: '4827' });
  await db.query('update users set active = false where id = $1', [off.id]);
  assert.equal((await call(c, 'PUT', '/api/attribution', { commune: 'NOTTO', user_id: off.id, assigned: true })).status, 409);
});

test('réinitialisation du code par le coordinateur : agents seulement, code affiché une fois, sessions fermées, journal', async () => {
  const coord = await createUser(COORD);
  const c = await cookieOf(COORD);
  const agent = await createUser({ phone: '221770000078', role: 'agent', password: 'ancienmotdepasse' });
  const token = await login(agent);
  const r = await call(c, 'POST', `/api/attribution/agents/${agent.id}/code`);
  assert.equal(r.status, 200);
  assert.match(r.data.secret, /^\d{4}$/);
  assert.equal((await api('GET', '/api/app/bootstrap', { token })).status, 401);
  assert.equal((await api('POST', '/api/auth/login', { body: { phone: agent.phone, password: agent.password } })).status, 401);
  assert.ok(await login({ phone: agent.phone, password: r.data.secret }));
  const ev = (await db.query('select actor_id, action from account_events where target_id = $1', [agent.id])).rows;
  assert.deepEqual(ev, [{ actor_id: coord.id, action: 'reset' }]);
  const admin = await createUser(ADMIN);
  const refused = await call(c, 'POST', `/api/attribution/agents/${admin.id}/code`);
  assert.equal(refused.status, 403);
  assert.equal((await call(c, 'POST', `/api/attribution/agents/${coord.id}/code`)).status, 403);
});

test('l’agent n’a pas accès à l’attribution', async () => {
  const agent = await createUser({ phone: '221770000079', role: 'agent', password: '4827' });
  const token = await login(agent);
  assert.equal((await api('GET', '/api/attribution', { token })).status, 403);
  assert.equal((await api('PUT', '/api/attribution', { token, body: { commune: 'X', user_id: agent.id, assigned: true } })).status, 403);
  assert.equal((await api('POST', `/api/attribution/agents/${agent.id}/code`, { token })).status, 403);
});

test('la page « Attribution » s’ouvre pour le coordinateur et l’admin, avec le lien dans le rail', async () => {
  await createUser(COORD);
  await createUser(ADMIN);
  await createUser({ phone: '221770000080', name: 'Cheikh Issa', role: 'agent', password: '4827' });
  await producer('THIEPPE');
  for (const u of [COORD, ADMIN]) {
    const cookie = await cookieOf(u);
    const r = await fetch(`${BASE}/attribution`, { headers: { cookie } });
    assert.equal(r.status, 200, u.role);
    const html = await r.text();
    assert.match(html, /Cheikh Issa/);
    assert.match(html, /Aucun agent/);
    assert.match(html, /href="\/attribution"/);
  }
});
