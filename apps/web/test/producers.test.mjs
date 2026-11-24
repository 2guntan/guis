import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, login, resetDb } from './helpers.mjs';

let token;
let agent;
beforeEach(async () => {
  await resetDb();
  agent = await createUser({ phone: '221770000001', role: 'agent', password: 'motdepasse' });
  token = await login(agent);
});
after(() => db.end());

const producer = (over = {}) => ({
  last_name: 'Diop',
  first_name: 'Awa',
  phone: '77 123 45 67',
  member_card: 'CM-001',
  sex: 'F',
  village: 'Village A',
  consent_at: '2026-11-23T10:00:00Z',
  seeds: [],
  ...over,
});

test('création d’un producteur, puis mise à jour par le même identifiant', async () => {
  const id = randomUUID();
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token, body: producer() })).status, 200);
  assert.equal((await api('PUT', `/api/app/producers/${id}`, { token, body: producer({ first_name: 'Awa Marie' }) })).status, 200);
  const { rows } = await db.query('select first_name, phone, consent_by, created_by from producers');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].first_name, 'Awa Marie');
  assert.equal(rows[0].phone, '221771234567', 'téléphone normalisé');
  assert.equal(rows[0].consent_by, agent.id);
  assert.equal(rows[0].created_by, agent.id);
});

test('le village saisi en texte libre rejoint la liste', async () => {
  await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ village: 'Nouveau village' }) });
  const { data } = await api('GET', '/api/app/bootstrap', { token });
  assert.ok(data.lists.villages.includes('Nouveau village'));
});

test('consentement obligatoire', async () => {
  const r = await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ consent_at: undefined }) });
  assert.equal(r.status, 422);
  assert.match(r.data.error, /consent/);
});

test('nom obligatoire, identifiant invalide refusé', async () => {
  assert.equal((await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ last_name: ' ' }) })).status, 422);
  assert.equal((await api('PUT', '/api/app/producers/pas-un-uuid', { token, body: producer() })).status, 422);
});

test('carte de membre en double : 409 ; téléphone partagé : accepté', async () => {
  await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer() });
  const dupCard = await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ first_name: 'Fatou' }) });
  assert.equal(dupCard.status, 409);
  assert.match(dupCard.data.error, /carte de membre/);
  const samePhone = await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ first_name: 'Fatou', member_card: 'CM-002' }) });
  assert.equal(samePhone.status, 200);
});

test('semences : création, modification, suppression', async () => {
  const id = randomUUID();
  const s1 = { id: randomUUID(), variety: 'Spunta', quantity_kg: 50, received_on: '2026-11-10' };
  const s2 = { id: randomUUID(), variety: 'Sahel', quantity_kg: 25, received_on: null };
  await api('PUT', `/api/app/producers/${id}`, { token, body: producer({ seeds: [s1, s2] }) });
  await api('PUT', `/api/app/producers/${id}`, { token, body: producer({ seeds: [{ ...s1, quantity_kg: 60 }], deleted_seed_ids: [s2.id] }) });
  const { rows } = await db.query('select id, variety, quantity_kg::float8 as kg from seed_distributions');
  assert.deepEqual(rows, [{ id: s1.id, variety: 'Spunta', kg: 60 }]);
});

test('une ligne de semence d’un autre producteur ne peut pas être reprise', async () => {
  const s = { id: randomUUID(), variety: 'Spunta', quantity_kg: 50 };
  await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ seeds: [s] }) });
  const r = await api('PUT', `/api/app/producers/${randomUUID()}`, { token, body: producer({ member_card: 'CM-9', seeds: [s] }) });
  assert.equal(r.status, 409);
});

test('quantité de semence nulle refusée', async () => {
  const r = await api('PUT', `/api/app/producers/${randomUUID()}`, {
    token,
    body: producer({ seeds: [{ id: randomUUID(), variety: 'Spunta', quantity_kg: 0 }] }),
  });
  assert.equal(r.status, 422);
});

test('chargement initial : compte, listes, producteurs et semences des agents de la même commune', async () => {
  await db.query(`insert into villages values ('Village B'); insert into varieties values ('Spunta')`);
  const other = await createUser({ phone: '221770000002', password: 'motdepasse' });
  // Les deux agents partagent une commune (ADR-0001) : la création de l'un y est rattachée et visible de l'autre.
  await db.query(`insert into communes values ('COMMUNE A'); insert into agent_communes values ('${agent.id}', 'COMMUNE A'), ('${other.id}', 'COMMUNE A')`);
  const otherToken = await login(other);
  const id = randomUUID();
  const seed = { id: randomUUID(), variety: 'Spunta', quantity_kg: 40, received_on: '2026-11-12' };
  await api('PUT', `/api/app/producers/${id}`, { token: otherToken, body: producer({ seeds: [seed] }) });
  const { status, data } = await api('GET', '/api/app/bootstrap', { token });
  assert.equal(status, 200);
  assert.equal(data.user.id, agent.id);
  assert.deepEqual(data.lists.varieties, ['Spunta']);
  assert.ok(data.lists.villages.includes('Village B'));
  assert.ok(data.lists.irrigation.includes('Goutte-à-goutte'));
  assert.ok(data.lists.water_sources.includes('Céane'));
  assert.equal(data.producers.length, 1);
  assert.equal(data.producers[0].id, id);
  assert.equal(data.producers[0].consent_at !== null, true);
  assert.deepEqual(data.seeds, [{ ...seed, producer_id: id }]);
  assert.deepEqual(data.fields, []);
});
