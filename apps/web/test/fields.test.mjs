import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, login, resetDb } from './helpers.mjs';

let token;
let producerId;
beforeEach(async () => {
  await resetDb();
  token = await login(await createUser());
  producerId = randomUUID();
  const r = await api('PUT', `/api/app/producers/${producerId}`, {
    token,
    body: { last_name: 'Diop', first_name: 'Awa', consent_at: '2026-11-23T10:00:00Z' },
  });
  assert.equal(r.status, 200);
});
after(() => db.end());

/** Carré de `side` mètres autour d'un point des Niayes, sommets dans l'ordre. */
function square(side = 100, lat = 15.05, lng = -16.95) {
  const dlat = side / 111_320 / 2;
  const dlng = side / (111_320 * Math.cos((lat * Math.PI) / 180)) / 2;
  return [
    [lat + dlat, lng - dlng],
    [lat + dlat, lng + dlng],
    [lat - dlat, lng + dlng],
    [lat - dlat, lng - dlng],
  ].map(([la, ln]) => ({ lat: la, lng: ln, accuracy_m: 4, captured_at: '2026-11-23T10:00:00Z' }));
}

const field = (over = {}) => ({
  producer_id: producerId,
  name: 'Champ 1',
  contour: square(100),
  area_declared_ha: 1.2,
  sown_on: '2026-11-15',
  irrigation: 'Goutte-à-goutte',
  water_source: 'Forage',
  ...over,
});

test('enregistrement d’un champ : la base calcule la surface mesurée', async () => {
  const id = randomUUID();
  const r = await api('PUT', `/api/app/fields/${id}`, { token, body: field() });
  assert.equal(r.status, 200, JSON.stringify(r.data));
  const { rows } = await db.query(
    `select area_measured_ha::float8 as m, area_declared_ha::float8 as d, to_char(sown_on, 'YYYY-MM-DD') as sown, irrigation, jsonb_array_length(contour) as n,
            st_npoints(geom) as pts from fields where id = $1`,
    [id],
  );
  assert.ok(Math.abs(rows[0].m - 1.0) < 0.01, `surface mesurée ${rows[0].m} ha`);
  assert.equal(rows[0].d, 1.2);
  assert.equal(rows[0].sown, '2026-11-15');
  assert.equal(rows[0].irrigation, 'Goutte-à-goutte');
  assert.equal(rows[0].n, 4, 'sommets bruts gardés');
  assert.equal(rows[0].pts, 5, 'anneau fermé');
});

test('le chargement initial renvoie le champ avec ses surfaces', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/fields/${id}`, { token, body: field() });
  const { data } = await api('GET', '/api/app/bootstrap', { token });
  const f = data.fields.find((x) => x.id === id);
  assert.equal(f.producer_id, producerId);
  assert.ok(Math.abs(f.area_measured_ha - 1) < 0.01);
  assert.equal(f.area_declared_ha, 1.2);
  assert.equal(f.sown_on, '2026-11-15');
  assert.equal(f.contour.length, 4);
});

test('un nouveau contour ou une nouvelle date de semis enfile un calcul satellite, sans doublon', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/fields/${id}`, { token, body: field() });
  await api('PUT', `/api/app/fields/${id}`, { token, body: field({ sown_on: '2026-11-16' }) });
  let { rows } = await db.query("select count(*)::int as n from jobs where field_id = $1 and status = 'queued'", [id]);
  assert.equal(rows[0].n, 1, 'un seul travail en attente par champ');
  await db.query("update jobs set status = 'done'");
  await api('PUT', `/api/app/fields/${id}`, { token, body: field({ sown_on: '2026-11-16', irrigation: 'Aspersion' }) });
  ({ rows } = await db.query("select count(*)::int as n from jobs where status = 'queued'"));
  assert.equal(rows[0].n, 0, 'changer l’irrigation ne relance pas le calcul');
  await api('PUT', `/api/app/fields/${id}`, { token, body: field({ contour: square(120) }) });
  ({ rows } = await db.query("select count(*)::int as n from jobs where status = 'queued'"));
  assert.equal(rows[0].n, 1);
});

test('champ sans contour accepté (GPS indisponible), sans calcul satellite', async () => {
  const id = randomUUID();
  const r = await api('PUT', `/api/app/fields/${id}`, { token, body: field({ contour: [] }) });
  assert.equal(r.status, 200);
  const { rows } = await db.query('select geom, area_measured_ha from fields where id = $1', [id]);
  assert.equal(rows[0].geom, null);
  assert.equal(rows[0].area_measured_ha, null);
  assert.equal((await db.query('select count(*)::int as n from jobs')).rows[0].n, 0);
});

test('contour qui se croise : 422 en français', async () => {
  const [a, b, c, d] = square(100);
  const r = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ contour: [a, c, b, d] }) });
  assert.equal(r.status, 422);
  assert.match(r.data.error, /se croise/);
});

test('contour de moins de 100 m² : 422', async () => {
  const r = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ contour: square(5) }) });
  assert.equal(r.status, 422);
  assert.match(r.data.error, /100 m²/);
});

test('champ d’un producteur inconnu : 409', async () => {
  const r = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ producer_id: randomUUID() }) });
  assert.equal(r.status, 409);
  assert.match(r.data.error, /producteur/);
});

test('un champ ne change pas de producteur', async () => {
  const id = randomUUID();
  await api('PUT', `/api/app/fields/${id}`, { token, body: field() });
  const other = randomUUID();
  await api('PUT', `/api/app/producers/${other}`, { token, body: { last_name: 'Fall', first_name: 'Ibou', consent_at: '2026-11-23T10:00:00Z' } });
  const r = await api('PUT', `/api/app/fields/${id}`, { token, body: field({ producer_id: other }) });
  assert.equal(r.status, 409);
});

test('surface déclarée négative refusée', async () => {
  const r = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ area_declared_ha: -1 }) });
  assert.equal(r.status, 422);
  assert.equal(r.data.error, 'Surface déclarée : doit être plus grand que 0.');
});

test('refus lisibles par l’agent : nom de la case, sans motif ni chemin technique', async () => {
  const date = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ sown_on: '12/11/2026' }) });
  assert.equal(date.status, 422);
  assert.equal(date.data.error, 'Date de semis : date invalide (jour, mois, année attendus).');
  const pts = square();
  pts[2] = { ...pts[2], lat: 120 };
  const point = await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: field({ contour: pts }) });
  assert.equal(point.status, 422);
  assert.equal(point.data.error, 'Point du contour n° 3, Latitude : ne doit pas dépasser 90.');
});
