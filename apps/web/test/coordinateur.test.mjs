// Profil coordinateur : tableau de bord en lecture seule (ticket #25, spec #24).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

const COORD = { phone: '221770000020', name: 'Coord Test', role: 'coordinator', password: 'coord-pass-123' };

/** Connexion au tableau de bord : renvoie le cookie de session, ou la redirection. */
async function dashboardLogin(u) {
  const r = await fetch(`${BASE}/connexion`, {
    method: 'POST',
    redirect: 'manual',
    body: new URLSearchParams({ phone: u.phone, password: u.password, suite: '/' }),
  });
  const cookie = (r.headers.get('set-cookie') ?? '').split(';')[0];
  return { location: r.headers.get('location'), cookie };
}

const page = (path, cookie) => fetch(BASE + path, { headers: { cookie }, redirect: 'manual' });

async function producer(commune = 'NOTTO', extra = {}) {
  const id = randomUUID();
  await db.query(`insert into producers (id, last_name, first_name, phone, commune, source, created_by) values ($1, 'BA', 'Awa', $2, $3, 'import', $4)`, [
    id,
    extra.phone ?? null,
    commune,
    extra.created_by ?? null,
  ]);
  return id;
}

test('le coordinateur se connecte au tableau de bord et ouvre toutes ses pages, sans export', async () => {
  await createUser(COORD);
  const { location, cookie } = await dashboardLogin(COORD);
  assert.equal(location, '/');
  assert.match(cookie, /^guis_session=/);
  for (const path of ['/', '/champs', '/producteurs', '/doublons']) {
    const r = await page(path, cookie);
    assert.equal(r.status, 200, path);
    const html = await r.text();
    assert.doesNotMatch(html, /href="\/api\/export/, `${path} : pas de bouton d’export`);
  }
});

test('l’admin garde l’export ; le coordinateur reçoit 403 sur l’export', async () => {
  const admin = await createUser({ phone: '221770000021', role: 'admin', password: 'admin-pass-123' });
  await createUser(COORD);
  const a = await dashboardLogin(admin);
  assert.match(await (await page('/producteurs', a.cookie)).text(), /href="\/api\/export/);
  assert.equal((await page('/api/export', a.cookie)).status, 200);
  const c = await dashboardLogin(COORD);
  assert.equal((await page('/api/export', c.cookie)).status, 403);
});

test('l’agent reste refusé au tableau de bord', async () => {
  const agent = await createUser({ phone: '221770000022', role: 'agent', password: 'agent-pass' });
  const { location } = await dashboardLogin(agent);
  assert.equal(location, '/login?erreur=role');
});

test('le coordinateur ne peut pas trancher un doublon ni modifier des données', async () => {
  await createUser(COORD);
  const { cookie } = await dashboardLogin(COORD);
  const id = await producer();
  const r = await fetch(`${BASE}/api/doublons/${id}`, { method: 'POST', redirect: 'manual', headers: { cookie }, body: new URLSearchParams({ action: 'distinct' }) });
  assert.equal(r.status, 403);
  const put = await fetch(`${BASE}/api/app/producers/${id}`, {
    method: 'PUT',
    headers: { cookie, 'content-type': 'application/json' },
    body: JSON.stringify({ last_name: 'X', first_name: 'Y', consent_at: new Date().toISOString(), seeds: [] }),
  });
  assert.equal(put.status, 403);
  const field = await fetch(`${BASE}/api/app/fields/${randomUUID()}`, { method: 'PUT', headers: { cookie, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(field.status, 403);
  const photo = await fetch(`${BASE}/api/photos/${randomUUID()}`, { method: 'PUT', headers: { cookie }, body: new Uint8Array([1, 2, 3]) });
  assert.equal(photo.status, 403);
});

test('la page des doublons montre les doublons au coordinateur, sans les boutons de décision', async () => {
  await createUser(COORD);
  const admin = await createUser({ phone: '221770000024', role: 'admin', password: 'admin-pass-123' });
  await producer('NOTTO', { phone: '221771112233' });
  const dup = randomUUID();
  await db.query(`insert into producers (id, last_name, first_name, phone, source, consent_at, possible_duplicate_of) select $1, 'BA', 'Awa', '221771112233', 'app', now(), array[id] from producers limit 1`, [dup]);
  const { cookie } = await dashboardLogin(COORD);
  const html = await (await page('/doublons', cookie)).text();
  assert.match(html, /Doublon possible/);
  assert.doesNotMatch(html, /Fusionner dans celui-ci|Ce sont deux personnes/);
  const a = await dashboardLogin(admin);
  assert.match(await (await page('/doublons', a.cookie)).text(), /Fusionner dans celui-ci/);
});

test('l’app Android refuse le coordinateur avec un message dédié', async () => {
  await createUser(COORD);
  const r = await api('POST', '/api/auth/login', { body: { phone: COORD.phone, password: COORD.password } });
  assert.equal(r.status, 403);
  assert.equal(r.data.code, 'dashboard_only');
  assert.equal(r.data.error, 'Ce compte s’utilise sur le tableau de bord.');
});

test('l’admin peut toujours se connecter à l’app', async () => {
  const admin = await createUser({ phone: '221770000023', role: 'admin', password: 'admin-pass-123' });
  assert.ok(await login(admin));
});

test('le coordinateur voit tous les producteurs, comme l’admin', async () => {
  const c = await createUser(COORD);
  await producer('NOTTO');
  await producer('THIEPPE');
  const visible = await db.query('select count(*)::int as n from producers p where producer_visible($1, p.id)', [c.id]);
  assert.equal(visible.rows[0].n, 2);
  const { cookie } = await dashboardLogin(COORD);
  const boot = await fetch(`${BASE}/api/app/bootstrap`, { headers: { cookie } });
  assert.equal(boot.status, 200);
  assert.equal((await boot.json()).producers.length, 2);
});
