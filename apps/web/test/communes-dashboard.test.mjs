// Tableau de bord : commune et comparaison des surfaces (ticket 14).
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import ExcelJS from 'exceljs';
import { BASE, createUser, db, resetDb } from './helpers.mjs';

let cookie;
// HTML affiché seulement : en développement, Next joint parfois les données du serveur dans des <script> de débogage.
const page = async (path) => (await (await fetch(`${BASE}${path}`, { headers: { cookie } })).text()).replace(/<script[\s\S]*?<\/script>/g, '');

beforeEach(async () => {
  await resetDb();
  await createUser({ phone: '221770000099', role: 'admin', password: 'admin-pass' });
  const r = await fetch(`${BASE}/connexion`, { method: 'POST', redirect: 'manual', body: new URLSearchParams({ phone: '770000099', password: 'admin-pass', suite: '/' }) });
  cookie = r.headers.get('set-cookie').split(';')[0];
  const a = randomUUID();
  await db.query(
    `insert into producers (id, last_name, first_name, phone, village, commune, area_declared_ha, area_validated_ha, source) values
       ($1, 'DIOP', 'Awa', '221770000011', 'VILLAGE UN', 'COMMUNE A', 2, 1.5, 'import'),
       ($2, 'À COMPLÉTER', 'Arouna', null, 'VILLAGE DEUX', 'COMMUNE B', 1, 0, 'import')`,
    [a, randomUUID()],
  );
  const lat = 15.05, lng = -16.95, d = 0.00045; // ≈ 0,97 ha
  const ring = [[lng - d, lat + d], [lng + d, lat + d], [lng + d, lat - d], [lng - d, lat - d], [lng - d, lat + d]];
  await db.query(
    `insert into fields (id, producer_id, name, geom) values ($1, $2, 'Champ 1', st_setsrid(st_geomfromgeojson($3), 4326))`,
    [randomUUID(), a, JSON.stringify({ type: 'Polygon', coordinates: [ring] })],
  );
});
after(() => db.end());

test('liste des producteurs : commune, surfaces, filtres commune et « à compléter »', async () => {
  const all = await page('/producteurs');
  assert.match(all, /COMMUNE A/);
  assert.match(all, /Toutes les communes/);
  assert.match(all, /Validée/);
  assert.match(all, /1,50 ha/);
  assert.match(all, /écart mesurée \/ validée/);
  assert.match(all, /À compléter \(1\)/);
  assert.match(all, /Téléphone à compléter/);
  const b = await page('/producteurs?commune=COMMUNE%20B');
  assert.match(b, /Arouna/);
  assert.doesNotMatch(b, /Awa DIOP/);
  const todo = await page('/producteurs?completer=1');
  assert.match(todo, /Arouna/);
  assert.doesNotMatch(todo, /Awa DIOP/);
});

test('accueil : chiffres par commune', async () => {
  const home = await page('/');
  assert.match(home, /Par commune/);
  assert.match(home, /COMMUNE A[\s\S]*?1<!-- --> \/ <!-- -->1/);
  assert.match(home, /1,5<!-- --> ha/);
});

test('export : commune et surfaces du producteur', async () => {
  const res = await fetch(`${BASE}/api/export`, { headers: { cookie } });
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(await res.arrayBuffer());
  const ws = wb.getWorksheet('Producteurs');
  const head = ws.getRow(1).values.slice(1);
  const col = (h) => head.indexOf(h) + 1;
  assert.ok(col('Commune') > 0 && col('Surface validée, fiche (ha)') > 0);
  const awa = ws.getSheetValues().slice(2).find((r) => r[1] === 'DIOP');
  assert.equal(awa[col('Commune')], 'COMMUNE A');
  assert.equal(awa[col('Surface déclarée, fiche (ha)')], 2);
  assert.equal(awa[col('Surface validée, fiche (ha)')], 1.5);
  assert.ok(Math.abs(awa[col('Surface mesurée, total (ha)')] - 0.97) < 0.05);
  assert.equal(awa[col('Champs')], 1);
  const fields = wb.getWorksheet('Champs');
  assert.equal(fields.getRow(2).getCell(fields.getRow(1).values.indexOf('Commune')).value, 'COMMUNE A');
});
