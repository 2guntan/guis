// Page « Utilisateurs » : lister, créer, modifier, réinitialiser (ticket #28, spec #24).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, beforeEach, test } from 'node:test';
import bcrypt from 'bcryptjs';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';
import { isObviousCode, generateCode } from '../scripts/secrets.mjs';

beforeEach(resetDb);
after(() => db.end());

const ADMIN = { phone: '221770000040', name: 'Admin Test', role: 'admin', password: 'admin-pass-123' };
const COORD = { phone: '221770000041', name: 'Coord Test', role: 'coordinator', password: 'coord-pass-123' };

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

test('réservé à l’admin : 403 pour le coordinateur et l’agent, page fermée au coordinateur', async () => {
  await createUser(COORD);
  const agent = await createUser({ phone: '221770000042', role: 'agent', password: '4827' });
  const c = await cookieOf(COORD);
  assert.equal((await call(c, 'GET', '/api/users')).status, 403);
  assert.equal((await call(c, 'POST', '/api/users', { name: 'X', phone: '770000050', role: 'agent' })).status, 403);
  const t = await login(agent);
  assert.equal((await api('GET', '/api/users', { token: t })).status, 403);
  const page = await fetch(`${BASE}/utilisateurs`, { headers: { cookie: c }, redirect: 'manual' });
  assert.equal(page.status, 307);
  const home = await (await fetch(`${BASE}/`, { headers: { cookie: c } })).text();
  assert.doesNotMatch(home, /href="\/utilisateurs"/, 'pas de lien pour le coordinateur');
});

test('création d’un agent : code de 4 chiffres renvoyé une fois, empreinte seule en base, connexion possible', async () => {
  const a = await admin();
  const r = await call(a.cookie, 'POST', '/api/users', { name: 'Awa Diop', phone: '77 123 45 67', role: 'agent' });
  assert.equal(r.status, 201);
  assert.match(r.data.secret, /^\d{4}$/);
  assert.equal(r.data.phone, '221771234567');
  const row = (await db.query('select password_hash from users where phone = $1', ['221771234567'])).rows[0];
  assert.notEqual(row.password_hash, r.data.secret);
  assert.ok(await bcrypt.compare(r.data.secret, row.password_hash));
  assert.ok(await login({ phone: '771234567', password: r.data.secret }));
  const list = await call(a.cookie, 'GET', '/api/users');
  const awa = list.data.users.find((u) => u.phone === '221771234567');
  assert.equal(awa.role, 'agent');
  assert.equal(JSON.stringify(list.data).includes(r.data.secret) && r.data.secret.length > 4, false, 'aucun secret dans la liste');
  assert.equal('password_hash' in awa, false);
});

test('création d’un coordinateur ou d’un admin : mot de passe d’au moins 10 caractères', async () => {
  const a = await admin();
  for (const role of ['coordinator', 'admin']) {
    const r = await call(a.cookie, 'POST', '/api/users', { name: `C ${role}`, phone: role === 'admin' ? '770000051' : '770000052', role });
    assert.equal(r.status, 201);
    assert.ok(r.data.secret.length >= 10, role);
  }
});

test('téléphone déjà utilisé : 409 ; téléphone invalide : 422', async () => {
  const a = await admin();
  assert.equal((await call(a.cookie, 'POST', '/api/users', { name: 'X', phone: '770000053', role: 'agent' })).status, 201);
  const dup = await call(a.cookie, 'POST', '/api/users', { name: 'Y', phone: '+221 77 000 00 53', role: 'agent' });
  assert.equal(dup.status, 409);
  assert.match(dup.data.error, /déjà utilisé/);
  assert.equal((await call(a.cookie, 'POST', '/api/users', { name: 'Z', phone: '1234567', role: 'agent' })).status, 422);
});

test('modification : nom et téléphone ; quitter le profil agent retire les attributions', async () => {
  const a = await admin();
  const agent = await createUser({ phone: '221770000054', name: 'Mansour', role: 'agent', password: '4827' });
  await db.query(`insert into communes (name) values ('NOTTO')`);
  await db.query(`insert into agent_communes (user_id, commune) values ($1, 'NOTTO')`, [agent.id]);
  const r = await call(a.cookie, 'PATCH', `/api/users/${agent.id}`, { name: 'Mansour Ba', phone: '77 856 16 08' });
  assert.equal(r.status, 200);
  assert.equal(r.data.phone, '221778561608');
  assert.equal((await db.query('select count(*)::int as n from agent_communes')).rows[0].n, 1, 'reste agent : attributions gardées');
  assert.equal((await call(a.cookie, 'PATCH', `/api/users/${agent.id}`, { role: 'coordinator' })).status, 200);
  assert.equal((await db.query('select count(*)::int as n from agent_communes')).rows[0].n, 0);
});

test('l’admin ne peut pas changer son propre profil', async () => {
  const a = await admin();
  const r = await call(a.cookie, 'PATCH', `/api/users/${a.id}`, { role: 'agent' });
  assert.equal(r.status, 409);
  assert.equal((await call(a.cookie, 'PATCH', `/api/users/${a.id}`, { name: 'Admin Renommé' })).status, 200);
});

test('réinitialisation : nouveau secret, sessions fermées, ancien secret refusé, blocage levé, journal', async () => {
  const a = await admin();
  const agent = await createUser({ phone: '221770000055', name: 'Ablaye', role: 'agent', password: 'ancienmotdepasse' });
  const token = await login(agent);
  for (let i = 0; i < 5; i++) await api('POST', '/api/auth/login', { body: { phone: agent.phone, password: 'faux' } });
  assert.equal((await api('POST', '/api/auth/login', { body: { phone: agent.phone, password: agent.password } })).status, 429);
  const r = await call(a.cookie, 'POST', `/api/users/${agent.id}/secret`);
  assert.equal(r.status, 200);
  assert.match(r.data.secret, /^\d{4}$/);
  assert.equal((await api('GET', '/api/app/bootstrap', { token })).status, 401, 'session fermée');
  assert.equal((await api('POST', '/api/auth/login', { body: { phone: agent.phone, password: agent.password } })).status, 401, 'ancien secret refusé');
  assert.ok(await login({ phone: agent.phone, password: r.data.secret }), 'blocage levé, nouveau code accepté');
  const ev = (await db.query(`select action, detail from account_events where target_id = $1`, [agent.id])).rows;
  assert.deepEqual(ev.map((e) => e.action), ['reset']);
  assert.equal(JSON.stringify(ev).includes(r.data.secret), false, 'aucun secret dans le journal');
  const list = await call(a.cookie, 'GET', '/api/users');
  const row = list.data.users.find((u) => u.id === agent.id);
  assert.ok(row.last_reset_at);
  assert.equal(row.last_reset_by, 'Admin Test');
});

test('un ancien mot de passe d’agent de 10 caractères reste accepté', async () => {
  const agent = await createUser({ phone: '221770000056', role: 'agent', password: 'k3mp9wxq2a' });
  assert.ok(await login(agent));
});

test('la dernière synchronisation est celle du dernier bootstrap', async () => {
  const a = await admin();
  const agent = await createUser({ phone: '221770000057', role: 'agent', password: '4827' });
  const before = (await call(a.cookie, 'GET', '/api/users')).data.users.find((u) => u.id === agent.id);
  assert.equal(before.last_sync_at, null);
  await api('GET', '/api/app/bootstrap', { token: await login(agent) });
  const afterSync = (await call(a.cookie, 'GET', '/api/users')).data.users.find((u) => u.id === agent.id);
  assert.ok(afterSync.last_sync_at);
});

test('la page « Utilisateurs » s’ouvre pour l’admin et liste les comptes', async () => {
  const a = await admin();
  await createUser({ phone: '221770000058', name: 'Cheikh Issa', role: 'agent', password: '4827' });
  const r = await fetch(`${BASE}/utilisateurs`, { headers: { cookie: a.cookie } });
  assert.equal(r.status, 200);
  const html = await r.text();
  assert.match(html, /Cheikh Issa/);
  assert.match(html, /Nouveau compte/);
});

test('générateur de codes : jamais de code évident', () => {
  for (const c of ['0000', '1111', '1234', '4321', '0123', '9876', '6789', '3210']) assert.ok(isObviousCode(c), c);
  assert.ok(isObviousCode('4567', '221771234567'));
  for (const c of ['4827', '1357', '2580']) assert.equal(isObviousCode(c, '221770000000'), false, c);
  const phone = '221778561608';
  for (let i = 0; i < 20000; i++) {
    const c = generateCode(phone);
    assert.match(c, /^\d{4}$/);
    assert.equal(isObviousCode(c, phone), false, c);
  }
});

test('load-attribution crée les nouveaux agents avec un code de 4 chiffres', async () => {
  await db.query(`insert into communes (name) values ('NOTTO')`);
  const dir = mkdtempSync(path.join(tmpdir(), 'guis-users-'));
  const f = path.join(dir, 'a.csv');
  writeFileSync(f, 'commune;nom_agent;telephone_agent\nNOTTO;Mansour Ba;778561608\n');
  const r = spawnSync('node', [path.resolve(import.meta.dirname, '../scripts/load-attribution.mjs'), f], { env: process.env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const code = r.stdout.match(/221778561608 Mansour Ba : (\S+)/)?.[1];
  assert.match(code ?? '', /^\d{4}$/);
  assert.ok(await login({ phone: '778561608', password: code }));
});
