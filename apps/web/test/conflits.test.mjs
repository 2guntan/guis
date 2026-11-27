import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, login, resetDb } from './helpers.mjs';

// Modifications concurrentes (ADR-0004, audit M4).
let agent;
let agentToken;
let adminToken;
beforeEach(async () => {
  await resetDb();
  agent = await createUser({ phone: '221770000001', role: 'agent', password: 'motdepasse' });
  agentToken = await login(agent);
  adminToken = await login(await createUser({ phone: '221770000009', name: 'Admin', role: 'admin', password: 'motdepasse-admin' }));
});
after(() => db.end());

const producer = (over = {}) => ({ last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z', seeds: [], ...over });
const editedAt = async (token, id) => (await api('GET', '/api/app/bootstrap', { token })).data.producers.find((p) => p.id === id).edited_at;

test('fiche modifiée ailleurs depuis le dernier chargement : 409, puis « Renvoyer » remplace', async () => {
  const id = randomUUID();
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token: agentToken, body: producer() })).status, 200);
  const seen = await editedAt(agentToken, id);
  assert.ok(seen, 'edited_at envoyé au téléphone');

  // L'admin modifie la fiche ; le téléphone de l'agent, resté hors ligne, envoie sa version plus ancienne.
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token: adminToken, body: producer({ first_name: 'Admin', base_edited_at: seen }) })).status, 200);
  const late = await api('PUT', `/api/app/producers/${id}`, { token: agentToken, body: producer({ first_name: 'Agent', base_edited_at: seen }) });
  assert.equal(late.status, 409);
  assert.match(late.data.error, /modifié par quelqu’un d’autre/);
  assert.equal((await db.query('select first_name from producers where id = $1', [id])).rows[0].first_name, 'Admin', 'rien écrasé');

  // « Renvoyer » : sans base, la version de l'agent remplace.
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token: agentToken, body: producer({ first_name: 'Agent' }) })).status, 200);
  assert.equal((await db.query('select first_name from producers where id = $1', [id])).rows[0].first_name, 'Agent');
});

test('les envois successifs du même agent ne sont jamais en conflit, ni une fiche jamais modifiée', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/producers/${id}`, { token: agentToken, body: producer({ base_edited_at: null }) });
  const seen = await editedAt(agentToken, id);
  for (const name of ['Un', 'Deux', 'Trois']) {
    const r = await api('PUT', `/api/app/producers/${id}`, { token: agentToken, body: producer({ first_name: name, base_edited_at: seen }) });
    assert.equal(r.status, 200, name);
  }
  // Producteur importé, jamais modifié par une personne : pas de conflit avec une base nulle.
  const imported = randomUUID();
  await db.query("insert into producers (id, last_name, first_name, source) values ($1, 'Sow', 'Fatou', 'import')", [imported]);
  assert.equal((await api('PUT', `/api/app/producers/${imported}`, { token: adminToken, body: producer({ base_edited_at: null }) })).status, 200);
});

test('champ modifié ailleurs : 409', async () => {
  const pid = randomUUID();
  const fid = randomUUID();
  await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: producer() });
  const field = (over = {}) => ({ producer_id: pid, name: 'Champ 1', contour: [], ...over });
  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: field() })).status, 200);
  const seen = (await api('GET', '/api/app/bootstrap', { token: agentToken })).data.fields.find((f) => f.id === fid).edited_at;
  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: adminToken, body: field({ name: 'Admin', base_edited_at: seen }) })).status, 200);
  const late = await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: field({ name: 'Agent', base_edited_at: seen }) });
  assert.equal(late.status, 409);
  assert.match(late.data.error, /Ce champ/);
});

test('bootstrap : versions de l’app réglées sur le serveur (audit M10)', async () => {
  const { data } = await api('GET', '/api/app/bootstrap', { token: agentToken });
  const num = (v) => (v && /^\d+$/.test(v) ? Number(v) : null);
  assert.deepEqual(data.app, {
    min_build: num(process.env.GUIS_MIN_APP_BUILD),
    latest_build: num(process.env.GUIS_LATEST_APP_BUILD),
    apk_url: process.env.GUIS_APK_URL || null,
  });
});
