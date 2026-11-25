// Blocage après 5 essais de connexion (ticket #27, ADR-0003).
import assert from 'node:assert/strict';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, resetDb } from './helpers.mjs';

beforeEach(resetDb);
after(() => db.end());

const AGENT = { phone: '221770000030', name: 'Agent Blocage', role: 'agent', password: '4827' };
const app = (phone, password) => api('POST', '/api/auth/login', { body: { phone, password } });
const web = (phone, password) =>
  fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone, password, suite: '/' }) });
const endBlock = (phone) => db.query(`update login_attempts set blocked_until = now() - interval '1 second' where phone = $1`, [phone]);

test('app : 5 codes faux bloquent 15 minutes, même le bon code est refusé', async () => {
  await createUser(AGENT);
  for (let i = 1; i <= 4; i++) assert.equal((await app(AGENT.phone, '0000')).status, 401, `essai ${i}`);
  const fifth = await app(AGENT.phone, '0000');
  assert.equal(fifth.status, 429);
  assert.equal(fifth.data.error, 'Trop d’essais. Réessayez dans 15 minutes ou appelez votre coordinateur.');
  const good = await app(AGENT.phone, AGENT.password);
  assert.equal(good.status, 429, 'le bon code est refusé pendant le blocage');
  const row = (await db.query('select blocked_until > now() + interval \'14 minutes\' as long from login_attempts where phone = $1', [AGENT.phone])).rows[0];
  assert.equal(row.long, true, 'blocage d’environ 15 minutes');
});

test('à la fin du blocage, la connexion refonctionne et le compteur repart de zéro', async () => {
  await createUser(AGENT);
  for (let i = 0; i < 5; i++) await app(AGENT.phone, '0000');
  await endBlock(AGENT.phone);
  assert.equal((await app(AGENT.phone, '0000')).status, 401, 'un échec après le blocage ne rebloque pas aussitôt');
  assert.equal((await app(AGENT.phone, AGENT.password)).status, 200);
  assert.equal((await db.query('select count(*)::int as n from login_attempts')).rows[0].n, 0);
});

test('une connexion réussie remet le compteur à zéro', async () => {
  await createUser(AGENT);
  for (let i = 0; i < 4; i++) await app(AGENT.phone, '0000');
  assert.equal((await app(AGENT.phone, AGENT.password)).status, 200);
  for (let i = 0; i < 4; i++) assert.equal((await app(AGENT.phone, '0000')).status, 401);
  assert.equal((await app(AGENT.phone, AGENT.password)).status, 200, 'toujours pas bloqué');
});

test('téléphone sans compte : même blocage, sans révéler l’absence de compte', async () => {
  const phone = '221770000031';
  const first = await app(phone, '0000');
  assert.equal(first.status, 401);
  assert.equal(first.data.error, 'Numéro ou mot de passe incorrect.');
  for (let i = 0; i < 3; i++) await app(phone, '0000');
  assert.equal((await app(phone, '0000')).status, 429);
});

test('le numéro est compté sous sa forme normalisée', async () => {
  await createUser(AGENT);
  for (let i = 0; i < 5; i++) await app(i % 2 ? '77 000 00 30' : '770000030', '0000');
  assert.equal((await app(AGENT.phone, AGENT.password)).status, 429);
});

test('tableau de bord : même blocage, avec message sur la page de connexion', async () => {
  await createUser({ phone: '221770000032', role: 'admin', password: 'admin-pass-123' });
  for (let i = 0; i < 4; i++) assert.equal((await web('770000032', 'faux')).headers.get('location'), '/login?erreur=identifiants');
  assert.equal((await web('770000032', 'faux')).headers.get('location'), '/login?erreur=bloque');
  assert.equal((await web('770000032', 'admin-pass-123')).headers.get('location'), '/login?erreur=bloque');
  const html = await (await fetch(`${BASE}/login?erreur=bloque`)).text();
  assert.match(html, /Trop d’essais/);
});

test('les échecs sur l’app et sur le tableau de bord s’additionnent', async () => {
  await createUser({ phone: '221770000033', role: 'admin', password: 'admin-pass-123' });
  for (let i = 0; i < 3; i++) await app('221770000033', 'faux');
  await web('770000033', 'faux');
  assert.equal((await web('770000033', 'faux')).headers.get('location'), '/login?erreur=bloque');
});
