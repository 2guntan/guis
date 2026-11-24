// Import de la fiche de visite-validation (ticket 10) sur un classeur fictif généré ici.
// Ne parle qu'à la base (DATABASE_URL), pas au serveur.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, beforeEach, test } from 'node:test';
import ExcelJS from 'exceljs';
import { NOM_A_COMPLETER, phoneOrNull, splitName } from '../scripts/import-fiche-validation.mjs';
import { db, resetDb } from './helpers.mjs';

const script = path.resolve(import.meta.dirname, '../scripts/import-fiche-validation.mjs');
const dir = mkdtempSync(path.join(tmpdir(), 'guis-fiche-'));

const HEAD = ['N°', 'DATE', 'NON ET PRENOM', 'TELEPHONE', 'ADRESSE', 'SUPERFECIE DECALARE \n(ha)', 'SUPERFECIE VALIDE (ha)',
  'NOMBRE DES SACS', 'TONNAGE', 'ETAT DE\n LA\n PARCELLES', 'FORAGE SOLAIRE PRESENT', "SYSTÈME\n D'IRIGUATION"];

/** Classeur fictif : feuille A (en-tête ligne 3, titre et responsable, ligne TOTAL), feuille B (en-tête ligne 2). */
async function fiche(name, { extraB = [] } = {}) {
  const wb = new ExcelJS.Workbook();
  const a = wb.addWorksheet('COMMUNE A');
  a.addRow(['FICHE DE VISITE ET DE VALIDATION SUR LE TERRAIN']);
  a.addRow(['COMMUNE : A', '', '', '', '', '', '', 'RESPONSABLE X TEL 770000000']);
  a.addRow(HEAD);
  a.addRow([1, new Date('2026-09-27'), 'MODOU LAYE EXEMPLE', 770000101, 'VILLAGE UN', 2, 1.5, 180, 4.5, 'Bon', 'Oui', 'Fonctionnel']);
  a.addRow([2, null, 'AWA FICTIF', 770000102, 'VILAGE UN', 1, 0.5, 60, 1.5, 'Bon', 'Oui', 'Fonctionnel']);
  a.addRow([3, null, 'AWA FICTIF', 770000102, 'VILLAGE UN', 0.5, 0.2, 24, 0.6, 'Bon', 'Oui', 'Fonctionnel']); // 2e champ → fusion
  a.addRow([4, null, 'IBOU TEST', 770000103, 'VILLAGE DEUX', 1, 1, 120, 3, 'Bon', 'Oui', 'Fonctionnel']);
  a.addRow([5, null, 'IBOU TEST', 770000103, 'VILLAGE DEUX', 1, null, null, null, null, null, 'PAS DE GUIDE']); // ressaisie
  a.addRow([6, null, 'AROUNA', 77000010, 'VILLAGE DEUX', 1, 0, 0, 0, null, null, 'PAS DE GUIDE']); // 1 mot, tél. invalide
  a.addRow([7, null, 'SANS CHAMP', 770000105, 'VILLAGE DEUX', 1, 0, 0, 0, null, null, 'PAS DE CHAMP']); // écarté
  a.addRow(['TOTAL DECLARE', null, null, null, null, 6.5]);
  const b = wb.addWorksheet('COMMUNE B');
  b.addRow(['FICHE DE VISITE ET DE VALIDATION SUR LE TERRAIN']);
  b.addRow(['N°', 'DATE', 'NON ET PRENOM', 'TELEPHONE', 'ADRESSE', 'SUPERFECIE DECALARE \n(ha)', 'SUPERFECIE VALIDE (ha)', "OBSERVATION\n D'EQUIPE"]);
  b.addRow([1, null, 'FATOU NDIAYE TEST', null, 'VILLAGE TROIS', 3, 2]);
  // Remarque dans une cellule fusionnée qui recouvre les superficies de deux producteurs (lignes 4 et 5).
  b.addRow([2, null, 'ABANDON UN', 770000301, 'VILLAGE TROIS', 'Abandone']);
  b.addRow([3, null, 'ABANDON DEUX', 770000302, 'VILLAGE TROIS']);
  b.mergeCells('F4:H5');
  b.getCell('F4').value = 'Abandone';
  // Pas visité : remarque fusionnée sur la ligne, producteur importé.
  b.addRow([4, null, 'INJOIGNABLE TEST', 770000303, 'VILLAGE TROIS', 1]);
  b.mergeCells('G6:H6');
  b.getCell('G6').value = 'PAS VISITE  INJOIGNABLE';
  for (const r of extraB) b.addRow(r);
  b.addRow([5]); // ligne numérotée vide
  // Libellé TOTAL fusionné qui déborde dans la colonne du nom.
  const t = b.addRow([null, 'TOTAL DECLAREE', null, null, null, 5]).number;
  b.mergeCells(`B${t}:E${t}`);
  const f = path.join(dir, name);
  await wb.xlsx.writeFile(f);
  return f;
}

function villages() {
  const f = path.join(dir, 'villages.csv');
  writeFileSync(f, 'Village lu (Excel);Nb producteurs;Village retenu;Statut\nVILLAGE UN;2;VILLAGE UN;inchangé\nVILAGE UN;1;VILLAGE UN;corrigé\nVILLAGE DEUX;3;VILLAGE DEUX;inchangé\n');
  return f;
}

function run(...args) {
  const r = spawnSync('node', [script, ...args], { env: process.env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}

const producers = async () =>
  (
    await db.query(
      `select commune, last_name, first_name, phone, village, area_declared_ha::float8 as declared, area_validated_ha::float8 as validated,
              source, consent_at from producers order by commune, last_name, first_name`,
    )
  ).rows;

beforeEach(resetDb);
after(() => db.end());

test('règles de nom et de téléphone', () => {
  assert.deepEqual(splitName('  MODOU LAYE  NDIAYE '), { first: 'Modou Laye', last: 'NDIAYE', incomplete: false });
  assert.deepEqual(splitName('AROUNA'), { first: 'Arouna', last: NOM_A_COMPLETER, incomplete: true });
  assert.equal(phoneOrNull(779988902), '221779988902');
  assert.equal(phoneOrNull('+221 77 998 89 02'), '221779988902');
  assert.equal(phoneOrNull(77998890), null);
  assert.equal(phoneOrNull('7799889021'), null);
  assert.equal(phoneOrNull(null), null);
});

test('import de la fiche : feuilles, écartés, fusion, ressaisie, noms et téléphones', async () => {
  const f = await fiche('fiche.xlsx');
  const r = run(f, '--villages', villages());
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Producteurs : 6 créé\(s\), 0 mis à jour, 0 inchangé\(s\)\. Lignes écartées : 3\. Lignes rejetées : 0\./);
  assert.match(r.out, /COMMUNE B ligne 4 : Abandone/);
  assert.match(r.out, /COMMUNE B ligne 5 : Abandone/);
  assert.match(r.out, /COMMUNE A ligne 10 : PAS DE CHAMP/);
  assert.match(r.out, /COMMUNE A ligne 5 \+ COMMUNE A ligne 6 : fusionnées/);
  assert.match(r.out, /COMMUNE A ligne 7 \+ COMMUNE A ligne 8 : ressaisie, COMMUNE A ligne 7 gardée/);
  assert.match(r.out, /COMMUNE A ligne 9 : « AROUNA »/);
  assert.match(r.out, /COMMUNE A ligne 9 : « 77000010 » invalide/);
  assert.match(r.out, /COMMUNE B ligne 3 : absent/);
  assert.match(r.out, /Villages absents de la table de correspondance \(gardés tels quels\) \(1\) :\n {2}VILLAGE TROIS \(2\)/);
  const n = (x) => ({ source: 'import', consent_at: null, ...x });
  const order = (a, b) => (a.commune + a.last_name + a.first_name).localeCompare(b.commune + b.last_name + b.first_name);
  assert.deepEqual((await producers()).sort(order), [
    n({ commune: 'COMMUNE A', last_name: 'EXEMPLE', first_name: 'Modou Laye', phone: '221770000101', village: 'VILLAGE UN', declared: 2, validated: 1.5 }),
    n({ commune: 'COMMUNE A', last_name: 'FICTIF', first_name: 'Awa', phone: '221770000102', village: 'VILLAGE UN', declared: 1.5, validated: 0.7 }),
    n({ commune: 'COMMUNE A', last_name: 'TEST', first_name: 'Ibou', phone: '221770000103', village: 'VILLAGE DEUX', declared: 1, validated: 1 }),
    n({ commune: 'COMMUNE A', last_name: NOM_A_COMPLETER, first_name: 'Arouna', phone: null, village: 'VILLAGE DEUX', declared: 1, validated: 0 }),
    n({ commune: 'COMMUNE B', last_name: 'TEST', first_name: 'Injoignable', phone: '221770000303', village: 'VILLAGE TROIS', declared: 1, validated: null }),
    n({ commune: 'COMMUNE B', last_name: 'TEST', first_name: 'Fatou Ndiaye', phone: null, village: 'VILLAGE TROIS', declared: 3, validated: 2 }),
  ].sort(order));
  assert.equal((await db.query('select count(*)::int as n from seed_distributions')).rows[0].n, 0, 'aucune semence');
  assert.deepEqual((await db.query('select name from communes order by name')).rows.map((x) => x.name), ['COMMUNE A', 'COMMUNE B']);
  assert.deepEqual((await db.query('select name from villages order by name')).rows.map((x) => x.name), ['VILLAGE DEUX', 'VILLAGE TROIS', 'VILLAGE UN']);
});

test('simulation : même compte rendu, rien d’écrit', async () => {
  const r = run(await fiche('sim.xlsx'), '--villages', villages(), '--simulation');
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /SIMULATION/);
  assert.match(r.out, /6 créé\(s\)/);
  assert.equal((await db.query('select count(*)::int as n from producers')).rows[0].n, 0);
  assert.equal((await db.query('select count(*)::int as n from villages')).rows[0].n, 0);
});

test('réimport : met à jour les superficies sans écraser les corrections du terrain, ne supprime rien', async () => {
  assert.equal(run(await fiche('v1.xlsx'), '--villages', villages()).code, 0);
  const same = run(await fiche('v1bis.xlsx'), '--villages', villages());
  assert.match(same.out, /0 créé\(s\), 0 mis à jour, 6 inchangé\(s\)/);

  // Corrections du terrain sur « Arouna » : nom, téléphone, village.
  await db.query(
    `update producers set last_name = 'CORRIGE', phone = '221770000199', village = 'VILLAGE UN' where first_name = 'Arouna'`,
  );
  // Nouvelle version : superficie de Fatou modifiée, nouveau producteur, Modou Laye retiré de la fiche.
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(await fiche('v2.xlsx', { extraB: [[3, null, 'NOUVEAU PRODUCTEUR', 770000201, 'VILLAGE TROIS', 1, 1]] }));
  wb.getWorksheet('COMMUNE B').getRow(3).getCell(7).value = 2.5;
  wb.getWorksheet('COMMUNE A').getRow(4).getCell(3).value = null;
  const v2 = path.join(dir, 'v2-modifie.xlsx');
  await wb.xlsx.writeFile(v2);

  const r = run(v2, '--villages', villages());
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /1 créé\(s\), 1 mis à jour, 4 inchangé\(s\)/);
  assert.match(r.out, /Producteurs en base absents de la fiche \(non supprimés\) \(1\) :\n {2}COMMUNE A : Modou Laye EXEMPLE/);
  const rows = await producers();
  assert.equal(rows.length, 7);
  const arouna = rows.find((x) => x.first_name === 'Arouna');
  assert.deepEqual([arouna.last_name, arouna.phone, arouna.village], ['CORRIGE', '221770000199', 'VILLAGE UN'], 'corrections gardées');
  assert.equal(rows.find((x) => x.first_name === 'Fatou Ndiaye').validated, 2.5);
});
