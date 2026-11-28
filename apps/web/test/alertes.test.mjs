// Alertes satellite marquées « vues » sur la fiche champ (db/migrations/0012_alertes_vues.sql).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, createUser, db, resetDb } from './helpers.mjs';

const DROP = { code: 'ndvi_drop', message: 'Chute de NDVI : -0,16 en 10 jours' };
const NO_EMERGENCE = { code: 'no_emergence', message: 'Pas de levée à J+35' };
let fieldId;

async function cookieFor(role, phone) {
  await createUser({ phone: `22177${phone}`, role, password: 'mot-de-passe' });
  const r = await fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone: `77${phone}`, password: 'mot-de-passe', suite: '/' }) });
  return r.headers.get('set-cookie').split(';')[0];
}
const setAlerts = (alerts) =>
  db.query(
    `insert into field_status (field_id, status, alerts) values ($1, 'growth', $2)
     on conflict (field_id) do update set alerts = excluded.alerts`,
    [fieldId, JSON.stringify(alerts)],
  );
const review = (cookie) => fetch(`${BASE}/api/champs/${fieldId}/alertes`, { method: 'POST', redirect: 'manual', headers: { cookie } });
const page = async (path, cookie) => (await fetch(BASE + path, { headers: { cookie } })).text();
const openAlerts = async () => (await db.query('select open_alerts(field_id, alerts) as a from field_status where field_id = $1', [fieldId])).rows[0].a;

beforeEach(async () => {
  await resetDb();
  const producer = randomUUID();
  fieldId = randomUUID();
  await db.query(`insert into producers (id, last_name, first_name, source) values ($1, 'DIOP', 'Awa', 'import')`, [producer]);
  await db.query(`insert into fields (id, producer_id, name) values ($1, $2, 'Champ 1')`, [fieldId, producer]);
  await setAlerts([DROP]);
});
after(() => db.end());

test('coordinateur : « Marquer comme vue » sort le champ de la liste à vérifier', async () => {
  const cookie = await cookieFor('coordinator', '0000050');
  assert.match(await page(`/champs/${fieldId}`, cookie), /Marquer comme vue/);
  assert.match(await page('/', cookie), /NDVI en baisse/);
  const r = await review(cookie);
  assert.equal(r.status, 303);
  assert.equal(r.headers.get('location'), `/champs/${fieldId}?vu=1#alertes`);
  assert.deepEqual(await openAlerts(), []);
  const fiche = await page(`/champs/${fieldId}?vu=1`, cookie);
  assert.match(fiche, /Alerte marquée comme vue/);
  assert.match(fiche, /vue par Agent Test/);
  assert.match(await page('/', cookie), /Aucun champ en alerte/);
  assert.match(await page('/champs?alerte=1', cookie), /À vérifier seulement \(0\)/);
});

test('une autre alerte sur le même champ reste à vérifier', async () => {
  const cookie = await cookieFor('admin', '0000051');
  await review(cookie);
  await setAlerts([DROP, NO_EMERGENCE]);
  assert.deepEqual((await openAlerts()).map((a) => a.code), ['no_emergence']);
});

test('une alerte qui disparaît puis revient est de nouveau à vérifier', async () => {
  const cookie = await cookieFor('admin', '0000052');
  await review(cookie);
  await setAlerts([]);
  assert.equal((await db.query('select count(*)::int as n from alert_reviews')).rows[0].n, 0);
  await setAlerts([DROP]);
  assert.deepEqual((await openAlerts()).map((a) => a.code), ['ndvi_drop']);
});

test('agent : pas le droit de marquer les alertes', async () => {
  await createUser({ phone: '221770000053', role: 'agent', password: 'mot-de-passe' });
  const login = await fetch(`${BASE}/api/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone: '221770000053', password: 'mot-de-passe' }) });
  const { token } = await login.json();
  const r = await fetch(`${BASE}/api/champs/${fieldId}/alertes`, { method: 'POST', redirect: 'manual', headers: { authorization: `Bearer ${token}` } });
  assert.notEqual(r.headers.get('location'), `/champs/${fieldId}?vu=1#alertes`);
  assert.deepEqual((await openAlerts()).map((a) => a.code), ['ndvi_drop']);
});
