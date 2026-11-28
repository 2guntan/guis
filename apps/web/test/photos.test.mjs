import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

// Un JPEG minimal (en-tête SOI/EOI) : le serveur ne décode pas l'image.
const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9]);

let agentToken;
let adminToken;
beforeEach(async () => {
  await resetDb();
  agentToken = await login(await createUser({ phone: '221770000001', role: 'agent' }));
  adminToken = await login(await createUser({ phone: '221770000002', role: 'admin' }));
});
after(() => db.end());

const put = (id, body = jpeg, headers = {}) =>
  api('PUT', `/api/photos/${id}`, { token: agentToken, body, headers: { 'content-type': 'image/jpeg', ...headers } });

test('dépôt d’une photo avec sa position et sa date, puis lecture par un admin', async () => {
  const id = randomUUID();
  const r = await put(id, jpeg, { 'x-lat': '15.05', 'x-lng': '-16.95', 'x-taken-at': '2026-11-23T10:00:00Z' });
  assert.equal(r.status, 200, JSON.stringify(r.data));
  const { rows } = await db.query('select lat, lng, taken_at, size_bytes, content_type from photos where id = $1', [id]);
  assert.deepEqual(
    { lat: rows[0].lat, lng: rows[0].lng, size: rows[0].size_bytes, type: rows[0].content_type, at: rows[0].taken_at.toISOString() },
    { lat: 15.05, lng: -16.95, size: jpeg.length, type: 'image/jpeg', at: '2026-11-23T10:00:00.000Z' },
  );
  const res = await fetch(`${BASE}/api/photos/${id}`, { headers: { authorization: `Bearer ${adminToken}` } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), jpeg);
});

test('un second dépôt du même identifiant ne réécrit rien (reprise après coupure)', async () => {
  const id = randomUUID();
  assert.equal((await put(id)).status, 200);
  const other = Uint8Array.from([...jpeg, 0]);
  const again = await put(id, other);
  assert.equal(again.status, 200);
  assert.equal(again.data.existing, true);
  const { rows } = await db.query('select size_bytes from photos where id = $1', [id]);
  assert.equal(rows[0].size_bytes, jpeg.length);
});

test('format refusé, photo vide refusée', async () => {
  const bad = await api('PUT', `/api/photos/${randomUUID()}`, { token: agentToken, body: jpeg, headers: { 'content-type': 'application/pdf' } });
  assert.equal(bad.status, 422);
  assert.match(bad.data.error, /Format/);
  assert.equal((await put(randomUUID(), new Uint8Array())).status, 400);
});

test('dépôt sans session refusé', async () => {
  const r = await api('PUT', `/api/photos/${randomUUID()}`, { body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  assert.equal(r.status, 401);
});

test('lecture d’une photo refusée à un agent, 404 pour une photo inconnue', async () => {
  const id = randomUUID();
  await put(id);
  assert.equal((await api('GET', `/api/photos/${id}`, { token: agentToken })).status, 403);
  assert.equal((await api('GET', `/api/photos/${randomUUID()}`, { token: adminToken })).status, 404);
});

test('la photo est rattachée au producteur et au champ, et n’est pas effacée par un envoi sans photo', async () => {
  const photo = randomUUID();
  await put(photo);
  const pid = randomUUID();
  const producer = { last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z' };
  await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { ...producer, photo_id: photo } });
  await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: producer });
  const { rows } = await db.query('select photo_id from producers where id = $1', [pid]);
  assert.equal(rows[0].photo_id, photo);
});

test('une photo déposée par un autre compte ne peut pas être rattachée par un agent (audit L12)', async () => {
  const otherToken = await login(await createUser({ phone: '221770000003', role: 'agent' }));
  const foreign = randomUUID();
  await api('PUT', `/api/photos/${foreign}`, { token: otherToken, body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  const own = randomUUID();
  await put(own);
  const producer = { last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z' };

  const pid = randomUUID();
  const stolen = await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { ...producer, photo_id: foreign } });
  assert.equal(stolen.status, 403);
  assert.match(stolen.data.error, /autre compte/);
  const fid = randomUUID();
  assert.equal((await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { ...producer, photo_id: own } })).status, 200);
  const field = { producer_id: pid, contour: [], photo_id: foreign };
  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: field })).status, 403);

  // L'admin rattache la photo ; l'agent peut ensuite renvoyer la fiche avec cette photo, déjà liée.
  assert.equal((await api('PUT', `/api/app/producers/${pid}`, { token: adminToken, body: { ...producer, photo_id: foreign } })).status, 200);
  assert.equal((await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { ...producer, photo_id: foreign } })).status, 200);
});

test('photos du champ : la liste envoyée remplace, cinq au plus, une photo d’un autre compte refusée', async () => {
  const pid = randomUUID();
  const fid = randomUUID();
  await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z' } });
  const ids = [randomUUID(), randomUUID(), randomUUID()];
  for (const id of ids) await put(id);
  const field = { producer_id: pid, contour: [] };
  const ids_of = async () => (await db.query('select photo_ids from fields where id = $1', [fid])).rows[0].photo_ids;

  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_ids: ids } })).status, 200);
  assert.deepEqual(await ids_of(), ids);
  // Une photo retirée quitte la fiche ; un envoi sans liste ne touche pas aux photos.
  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_ids: [ids[0], ids[2]] } })).status, 200);
  assert.equal((await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: field })).status, 200);
  assert.deepEqual(await ids_of(), [ids[0], ids[2]]);

  const six = await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_ids: Array.from({ length: 6 }, () => randomUUID()) } });
  assert.equal(six.status, 422);
  assert.match(six.data.error, /Photos du champ : trop nombreux \(5 au plus\)/);

  const otherToken = await login(await createUser({ phone: '221770000003', role: 'agent' }));
  const foreign = randomUUID();
  await api('PUT', `/api/photos/${foreign}`, { token: otherToken, body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  const stolen = await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_ids: [ids[0], foreign] } });
  assert.equal(stolen.status, 403);
});

test('ancienne app (une seule photo) : sa photo s’ajoute si elle manque, rien n’est retiré', async () => {
  const pid = randomUUID();
  const fid = randomUUID();
  await api('PUT', `/api/app/producers/${pid}`, { token: agentToken, body: { last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z' } });
  const ids = [randomUUID(), randomUUID(), randomUUID()];
  for (const id of ids) await put(id);
  const field = { producer_id: pid, contour: [] };
  const ids_of = async () => (await db.query('select photo_ids from fields where id = $1', [fid])).rows[0].photo_ids;

  // Création par une ancienne app : une photo.
  await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_id: ids[0] } });
  assert.deepEqual(await ids_of(), [ids[0]]);
  // Nouvelle app : trois photos. L'ancienne app renvoie sa photo (déjà là) : rien ne change.
  await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_ids: ids } });
  await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_id: ids[0] } });
  assert.deepEqual(await ids_of(), ids);
  // Une photo absente de la liste est ajoutée à la fin.
  const extra = randomUUID();
  await put(extra);
  await api('PUT', `/api/app/fields/${fid}`, { token: agentToken, body: { ...field, photo_id: extra } });
  assert.deepEqual(await ids_of(), [...ids, extra]);

  // L'app reçoit la liste et, pour une ancienne version, la première photo.
  const boot = await api('GET', '/api/app/bootstrap', { token: agentToken });
  const f = boot.data.fields.find((x) => x.id === fid);
  assert.deepEqual(f.photo_ids, [...ids, extra]);
  assert.equal(f.photo_id, ids[0]);
});
