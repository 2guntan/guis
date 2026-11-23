// Test de bout en bout du tableau de bord, dans un vrai navigateur (Playwright, Chromium).
// Il parle au serveur lancé (GUIS_TEST_URL) et prépare ses données par l'API de l'app, comme un agent.
//   GUIS_TEST_URL=https://localhost DATABASE_URL=… node --test e2e/
// La base est vidée : jamais contre la production.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { chromium } from 'playwright';
import { BASE, api, createUser, db, login, resetDb } from '../test/helpers.mjs';

let browser;
let fieldId;
const SHOTS = process.env.E2E_SCREENSHOTS;

function square(side, lat, lng) {
  const dlat = side / 111_320 / 2;
  const dlng = side / (111_320 * Math.cos((lat * Math.PI) / 180)) / 2;
  return [
    [lat + dlat, lng - dlng],
    [lat + dlat, lng + dlng],
    [lat - dlat, lng + dlng],
    [lat - dlat, lng - dlng],
  ].map(([la, ln]) => ({ lat: la, lng: ln, accuracy_m: 4 }));
}

before(async () => {
  await resetDb();
  await createUser({ phone: '221770000009', name: 'Admin Test', role: 'admin', password: 'admin-pass' });
  const token = await login(await createUser({ phone: '221770000001', name: 'Agent Test', role: 'agent', password: 'agent-pass' }));
  const producers = [
    { id: randomUUID(), last_name: 'Diop', first_name: 'Awa', village: 'Village A', seeds: [{ id: randomUUID(), variety: 'Spunta', quantity_kg: 50, received_on: '2026-11-10' }] },
    { id: randomUUID(), last_name: 'Fall', first_name: 'Ibou', village: 'Village B', seeds: [] },
  ];
  for (const p of producers) {
    const r = await api('PUT', `/api/app/producers/${p.id}`, { token, body: { ...p, consent_at: '2026-11-23T10:00:00Z' } });
    assert.equal(r.status, 200);
  }
  fieldId = randomUUID();
  await api('PUT', `/api/app/fields/${fieldId}`, {
    token,
    body: { producer_id: producers[0].id, name: 'Champ du puits', contour: square(100, 15.05, -16.95), area_declared_ha: 1.5, sown_on: '2026-11-15', irrigation: 'Goutte-à-goutte', water_source: 'Forage' },
  });
  await api('PUT', `/api/app/fields/${randomUUID()}`, { token, body: { producer_id: producers[0].id, name: 'Champ 2', contour: square(150, 15.052, -16.953), area_declared_ha: 2 } });
  await db.query(
    `insert into field_status (field_id, status, alerts, last_ndvi) values ($1, 'emergence', '[{"code":"ndvi_drop","message":"Chute de NDVI de 0,20 entre deux images"}]', 0.31)`,
    [fieldId],
  );
  browser = await chromium.launch();
});
after(async () => {
  await browser?.close();
  await db.end();
});

async function signIn(page, phone, password) {
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/login/);
  await page.getByLabel('Numéro de téléphone').fill(phone);
  await page.getByLabel('Mot de passe').fill(password);
  await page.getByRole('button', { name: 'Se connecter' }).click();
}

test('un admin voit les chiffres clés, la carte, la liste et la fiche d’un champ', async () => {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, acceptDownloads: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await signIn(page, '77 000 00 09', 'admin-pass');
  await page.waitForURL(`${BASE}/`);

  const kpis = page.getByRole('region', { name: 'Chiffres clés' });
  await assert.doesNotReject(kpis.getByText('Producteurs').waitFor());
  assert.match(await kpis.innerText(), /Producteurs\s+2\s+1 sans champ relevé/i);
  assert.match(await kpis.innerText(), /Champs relevés\s+2/i);
  assert.match(await kpis.innerText(), /Semences distribuées\s+50 kg/i);
  assert.match(await kpis.innerText(), /Champs en alerte\s+1/i);
  await page.locator('.leaflet-container path.leaflet-interactive').first().waitFor();
  assert.equal(await page.locator('.leaflet-container path.leaflet-interactive').count(), 2, 'deux contours sur la carte');
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/accueil.png` });

  await page.getByRole('link', { name: 'Champs', exact: true }).first().click();
  await page.waitForURL(/\/champs/);
  assert.equal(await page.locator('tbody tr').count(), 2);
  await page.getByLabel('En alerte').click(); // case pilotée par l'URL
  await page.waitForURL(/alerte=1/);
  await page.waitForFunction(() => document.querySelectorAll('tbody tr').length === 1);
  assert.match(await page.locator('tbody').innerText(), /Awa DIOP[\s\S]*Champ du puits[\s\S]*Village A[\s\S]*-3[34] %[\s\S]*Levée[\s\S]*1 alerte/);
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/champs.png` });

  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: 'Exporter en Excel' }).click()]);
  assert.match(download.suggestedFilename(), /^guis-\d{4}-\d{2}-\d{2}\.xlsx$/);
  assert.ok((await download.path()) !== null, 'fichier téléchargé');

  await page.getByRole('link', { name: 'Awa DIOP' }).click();
  await page.waitForURL(new RegExp(`/champs/${fieldId}`));
  const body = await page.locator('main').innerText();
  assert.match(body, /Surface mesurée \(GPS\)\s+(0,99|1) ha/);
  assert.match(body, /Surface déclarée\s+1,5 ha/);
  assert.match(body, /Date de semis\s+15 nov\. 2026/);
  assert.match(body, /Goutte-à-goutte/);
  assert.match(body, /Chute de NDVI de 0,20/);
  assert.match(body, /Spunta — 50 kg, reçue le 10 nov\. 2026/);
  await page.locator('.leaflet-container path.leaflet-interactive').first().waitFor();
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/fiche.png`, fullPage: true });

  await page.getByRole('link', { name: 'Producteurs' }).first().click();
  await page.waitForURL(/\/producteurs/);
  assert.match(await page.locator('tbody').innerText(), /Ibou FALL[\s\S]*Aucun champ relevé/);
  assert.deepEqual(errors, []);
  await ctx.close();
});

test('un agent est refusé, un mauvais mot de passe aussi', async () => {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  await signIn(page, '770000001', 'agent-pass');
  await page.waitForURL(/\/login\?erreur=role/);
  assert.match(await page.locator('p[role=alert]').innerText(), /réservé aux administrateurs/);
  await signIn(page, '770000009', 'faux');
  await page.waitForURL(/erreur=identifiants/);
  assert.match(await page.locator('p[role=alert]').innerText(), /Numéro ou mot de passe incorrect/);
  const res = await page.goto(`${BASE}/champs`);
  assert.match(res.url(), /\/login/, 'pas de page sans session');
  await ctx.close();
});

test('déconnexion', async () => {
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  await signIn(page, '770000009', 'admin-pass');
  await page.waitForURL(`${BASE}/`);
  await page.getByTitle('Se déconnecter').click();
  await page.waitForURL(/\/login/);
  await page.goto(`${BASE}/`);
  await page.waitForURL(/\/login/);
  await ctx.close();
});
