import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, test } from 'node:test';
import ExcelJS from 'exceljs';
import { BASE, api, createUser, db, login, resetDb } from './helpers.mjs';

let admin;
let agent;
let awa;
beforeEach(async () => {
  await resetDb();
  admin = await login(await createUser({ phone: '221770000009', role: 'admin' }));
  agent = await login(await createUser({ phone: '221770000001', role: 'agent', name: 'Agent Test' }));
  awa = randomUUID();
  const ibou = randomUUID();
  await api('PUT', `/api/app/producers/${awa}`, {
    token: agent,
    body: { last_name: 'Diop', first_name: 'Awa', sex: 'F', village: 'Village A', consent_at: '2026-11-23T10:00:00Z', seeds: [{ id: randomUUID(), variety: 'Spunta', quantity_kg: 50.5, received_on: '2026-11-10' }] },
  });
  await api('PUT', `/api/app/producers/${ibou}`, { token: agent, body: { last_name: 'Fall', first_name: 'Ibou', village: 'Village B', consent_at: '2026-11-23T10:00:00Z' } });
  const lat = 15.05, lng = -16.95, d = 0.00045;
  await api('PUT', `/api/app/fields/${randomUUID()}`, {
    token: agent,
    body: {
      producer_id: awa, name: 'Champ 1', area_declared_ha: 1.2, sown_on: '2026-11-15', irrigation: 'Raie',
      contour: [[lat + d, lng - d], [lat + d, lng + d], [lat - d, lng + d], [lat - d, lng - d]].map(([a, b]) => ({ lat: a, lng: b })),
    },
  });
  await api('PUT', `/api/app/fields/${randomUUID()}`, { token: agent, body: { producer_id: ibou, name: 'Sans contour' } });
});
after(() => db.end());

async function download(qs = '', token = admin) {
  const res = await fetch(`${BASE}/api/export${qs}`, { headers: { authorization: `Bearer ${token}` } });
  return res;
}
async function workbook(res) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(await res.arrayBuffer());
  return wb;
}
const rows = (ws) => ws.getSheetValues().slice(2).map((r) => r.slice(1));

test('export : trois feuilles, dates et nombres au format Excel', async () => {
  const res = await download();
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-disposition'), /attachment; filename="guis-\d{4}-\d{2}-\d{2}\.xlsx"/);
  const wb = await workbook(res);
  assert.deepEqual(wb.worksheets.map((w) => w.name), ['Producteurs', 'Semences', 'Champs']);

  const p = wb.getWorksheet('Producteurs');
  assert.deepEqual(p.getRow(1).values.slice(1, 4), ['Nom', 'Prénom', 'Téléphone']);
  assert.equal(rows(p).length, 2);
  assert.equal(rows(p)[0][4], 'Femme');
  assert.ok(rows(p)[0][6] instanceof Date, 'consentement en date Excel');

  const s = rows(wb.getWorksheet('Semences'));
  assert.deepEqual(s.map((r) => [r[0], r[3], r[4]]), [['Awa DIOP', 'Spunta', 50.5]]);
  assert.equal(s[0][5].toISOString().slice(0, 10), '2026-11-10');

  const f = wb.getWorksheet('Champs');
  const header = f.getRow(1).values.slice(1);
  const col = (name) => header.indexOf(name);
  const champs = rows(f);
  assert.equal(champs.length, 2);
  const c1 = champs.find((r) => r[col('Champ')] === 'Champ 1');
  assert.equal(typeof c1[col('Surface mesurée (ha)')], 'number');
  assert.ok(Math.abs(c1[col('Surface mesurée (ha)')] - 1) < 0.05);
  assert.equal(c1[col('Surface déclarée (ha)')], 1.2);
  assert.equal(typeof c1[col('Écart (%)')], 'number');
  assert.equal(c1[col('Semis')].toISOString().slice(0, 10), '2026-11-15');
  assert.equal(c1[col('Statut satellite')], 'En attente d’images');
  assert.ok(Math.abs(c1[col('Latitude du centre')] - 15.05) < 1e-4);
  assert.equal(c1[col('Agent')], 'Agent Test');
  const c2 = champs.find((r) => r[col('Champ')] === 'Sans contour');
  assert.equal(c2[col('Statut satellite')], 'Sans contour');
});

test('export filtré : mêmes filtres que la liste des champs', async () => {
  const wb = await workbook(await download('?village=Village%20A'));
  assert.equal(rows(wb.getWorksheet('Champs')).length, 1);
  assert.equal(rows(wb.getWorksheet('Producteurs')).length, 1);
  assert.equal(rows(wb.getWorksheet('Semences')).length, 1);
});

test('export réservé aux admins', async () => {
  assert.equal((await download('', agent)).status, 403);
  assert.equal((await fetch(`${BASE}/api/export`)).status, 401);
});
