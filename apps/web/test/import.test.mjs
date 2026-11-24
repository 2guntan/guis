import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, beforeEach, test } from 'node:test';
import { api, createUser, db, login, resetDb } from './helpers.mjs';

const scripts = path.resolve(import.meta.dirname, '../scripts');
const dir = mkdtempSync(path.join(tmpdir(), 'guis-import-'));

function run(script, ...args) {
  const r = spawnSync('node', [path.join(scripts, script), ...args], { env: process.env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}
function csv(name, text) {
  const f = path.join(dir, name);
  writeFileSync(f, text);
  return f;
}

beforeEach(resetDb);
after(() => db.end());

test('listes : villages et variétés, sans doublon', async () => {
  const v = csv('v.csv', 'Nom\nVillage A\nVillage B\nVillage A\n');
  const s = csv('s.csv', '﻿nom\nSpunta\n');
  assert.equal(run('load-lists.mjs', '--villages', v, '--varietes', s).code, 0);
  const again = run('load-lists.mjs', '--villages', v);
  assert.match(again.out, /0 ajouté\(s\), 2 déjà présent/);
  assert.deepEqual((await db.query('select name from villages order by name')).rows.map((r) => r.name), ['Village A', 'Village B']);
  assert.deepEqual((await db.query('select name from varieties')).rows.map((r) => r.name), ['Spunta']);
});

test('import des distributions : producteurs et semences, puis réimport sans rien créer', async () => {
  const file = path.resolve(scripts, 'exemples/distributions.csv');
  const first = run('import-distributions.mjs', file);
  assert.equal(first.code, 0, first.out);
  assert.match(first.out, /Producteurs : 2 créé\(s\), 0 retrouvé\(s\)\. Semences : 3 ligne\(s\) créée\(s\)/);
  const second = run('import-distributions.mjs', file);
  assert.match(second.out, /Producteurs : 0 créé\(s\), 2 retrouvé\(s\)\. Semences : 0 ligne\(s\) créée\(s\), 3 déjà présente\(s\)/);
  const { rows } = await db.query(
    `select p.last_name, p.phone, p.member_card, p.sex, p.source, p.consent_at, sum(s.quantity_kg)::float8 as kg,
            min(to_char(s.received_on, 'YYYY-MM-DD')) as first
       from producers p join seed_distributions s on s.producer_id = p.id group by p.id order by p.last_name`,
  );
  assert.deepEqual(rows, [
    { last_name: 'EXEMPLE', phone: '221770000011', member_card: 'CM-0001', sex: 'F', source: 'import', consent_at: null, kg: 75, first: '2026-11-10' },
    { last_name: 'FICTIF', phone: '221770000012', member_card: null, sex: 'H', source: 'import', consent_at: null, kg: 100, first: '2026-11-11' },
  ]);
  assert.ok((await db.query("select 1 from varieties where name = 'Sahel'")).rowCount, 'variété ajoutée à la liste');
  assert.ok((await db.query("select 1 from villages where name = 'Village Exemple B'")).rowCount, 'village ajouté à la liste');
});

test('un producteur déjà saisi dans l’app est retrouvé par sa carte de membre', async () => {
  const token = await login(await createUser());
  const id = '11111111-1111-4111-8111-111111111111';
  await api('PUT', `/api/app/producers/${id}`, {
    token,
    body: { last_name: 'Diop', first_name: 'Awa', member_card: 'cm-0001', consent_at: '2026-11-23T10:00:00Z' },
  });
  const r = run('import-distributions.mjs', csv('d.csv', 'Nom;Prénom;Téléphone;Carte membre;Sexe;Village;Variété;Quantité kg;Date réception\nDIOP;Awa;;CM-0001;F;;Spunta;40,5;23/11/2026\n'));
  assert.match(r.out, /0 créé\(s\), 1 retrouvé/);
  const { rows } = await db.query('select producer_id, quantity_kg::float8 as kg from seed_distributions');
  assert.deepEqual(rows, [{ producer_id: id, kg: 40.5 }]);
});

test('lignes invalides rejetées avec leur motif, les autres importées', async () => {
  const r = run(
    'import-distributions.mjs',
    csv('bad.csv', 'nom,prenom,telephone,sexe,variete,quantite_kg,date_reception\n,Awa,,,Spunta,10,\nNdiaye,Ibou,12,,Spunta,10,\nSarr,Fatou,,X,,,\nFall,Ali,,,Spunta,zéro,\nFaye,Ami,,,Spunta,5,32/13/2026x\nSy,Binta,,F,Spunta,"7",\n'),
  );
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Producteurs : 1 créé\(s\)/);
  assert.match(r.out, /Lignes rejetées : 5/);
  assert.match(r.out, /ligne 2 : nom et prénom obligatoires/);
  assert.match(r.out, /ligne 3 : téléphone « 12 » invalide/);
  assert.match(r.out, /ligne 4 : sexe « X »/);
  assert.match(r.out, /ligne 5 : quantité « zéro » invalide/);
  assert.match(r.out, /ligne 6 : date illisible/);
});

test('les producteurs importés arrivent dans l’app, consentement à recueillir', async () => {
  run('import-distributions.mjs', path.resolve(scripts, 'exemples/distributions.csv'));
  // Sans commune, les producteurs de ce fichier ne sont visibles que de l'admin (ADR-0001).
  const token = await login(await createUser({ role: 'admin' }));
  const { data } = await api('GET', '/api/app/bootstrap', { token });
  assert.equal(data.producers.length, 2);
  assert.ok(data.producers.every((p) => p.source === 'import' && p.consent_at === null));
  assert.equal(data.seeds.length, 3);
  // L'agent recueille le consentement : le producteur passe par l'API comme les autres.
  const p = data.producers[0];
  const r = await api('PUT', `/api/app/producers/${p.id}`, { token, body: { last_name: p.last_name, first_name: p.first_name, consent_at: '2026-11-24T09:00:00Z' } });
  assert.equal(r.status, 200);
  const { rows } = await db.query('select consent_at, source from producers where id = $1', [p.id]);
  assert.equal(rows[0].consent_at.toISOString(), '2026-11-24T09:00:00.000Z');
  assert.equal(rows[0].source, 'import');
});

test('la base refuse un producteur saisi dans l’app sans consentement', async () => {
  await assert.rejects(
    db.query(`insert into producers (id, last_name, first_name, source) values (gen_random_uuid(), 'X', 'Y', 'app')`),
    /producers_consent_required/,
  );
});

test('deux distributions identiques le même jour sont deux lignes, et le réimport n’en ajoute pas', async () => {
  const f = csv('twice.csv', 'nom;prenom;carte_membre;variete;quantite_kg;date_reception\nDiop;Awa;CM-7;Spunta;25;10/11/2026\nDiop;Awa;CM-7;Spunta;25;10/11/2026\n');
  assert.match(run('import-distributions.mjs', f).out, /Semences : 2 ligne\(s\) créée\(s\)/);
  assert.match(run('import-distributions.mjs', f).out, /Semences : 0 ligne\(s\) créée\(s\), 2 déjà présente/);
  assert.equal((await db.query('select sum(quantity_kg)::float8 as kg from seed_distributions')).rows[0].kg, 50);
});
