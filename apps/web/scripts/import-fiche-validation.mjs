// Importe la fiche de visite-validation de la coopérative (classeur Excel gardé hors de git).
// Voir CONTEXT.md pour le vocabulaire et 2guntan/guis#13 pour les règles.
//
//   docker compose exec web node scripts/import-fiche-validation.mjs /tmp/fiche.xlsx --villages /tmp/villages-correspondance.xlsx [--simulation]
//
// Classeur : une feuille par commune (le nom de la feuille). L'en-tête est la ligne dont la
// première cellule vaut « N° » ; colonnes reconnues par leur libellé (nom et prénom, téléphone,
// adresse, superficie déclarée, superficie validée, système d'irrigation / observation pour les
// remarques). Les lignes sans nom (TOTAL, lignes numérotées vides) sont ignorées.
// Correspondance des villages : classeur ou CSV aux colonnes « Village lu » et « Village retenu ».
//
// Règles :
// - écarté : superficie validée nulle ET remarque « pas de champ », « pas de parcelle », « abandon… » ou « non validé »
//   (la remarque peut être dans une cellule fusionnée qui recouvre les superficies) ;
// - nom = dernier mot (majuscules), prénom = le reste ; un seul mot → nom « À COMPLÉTER » ;
// - téléphone absent ou invalide → producteur sans téléphone, signalé ;
// - même commune + téléphone + nom deux fois : une seule ligne avec superficie validée → on la garde,
//   plusieurs → fusion avec superficies additionnées ;
// - pas de semence ni de dotation : les remises sont saisies dans l'app ;
// - réimport : retrouvé par sa clé d'import (figée) ; seules la commune et les superficies sont mises à
//   jour, jamais le nom, le téléphone ni le village (corrigés sur le terrain) ; rien n'est supprimé.
// Avec --simulation, tout est fait dans une transaction annulée : même compte rendu, rien d'écrit.
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import ExcelJS from 'exceljs';
import pg from 'pg';
import { normalizeHeader, parseCsv } from './csv.mjs';

export const NOM_A_COMPLETER = 'À COMPLÉTER';
const EXCLUDED = ['PAS DE CHAMP', 'PAS DE PARCELLE', 'ABANDON', 'NON VALIDE'];

const fold = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toUpperCase();
const spaces = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();
const titleCase = (s) => s.toLowerCase().replace(/(^|[\s'-])(\p{L})/gu, (_, sep, c) => sep + c.toUpperCase());

/** Valeur lisible d'une cellule exceljs (formules, texte enrichi, liens). */
function cellValue(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'object' && !(v instanceof Date)) {
    if ('result' in v) return cellValue(v.result);
    if (Array.isArray(v.richText)) return v.richText.map((t) => t.text).join('');
    if ('text' in v) return cellValue(v.text);
    if ('error' in v) return null;
  }
  return v;
}

function number(v, what) {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(String(v).replace(',', '.').replace(/\s/g, ''));
  if (!Number.isFinite(n) || n < 0) throw new Error(`${what} « ${v} » illisible`);
  return n;
}

/** « MODOU LAYE NDIAYE » → { first: 'Modou Laye', last: 'NDIAYE' }. */
export function splitName(full) {
  const words = spaces(full).split(' ').filter(Boolean);
  if (words.length === 1) return { first: titleCase(words[0]), last: NOM_A_COMPLETER, incomplete: true };
  return { first: titleCase(words.slice(0, -1).join(' ')), last: words.at(-1).toUpperCase(), incomplete: false };
}

/** Téléphone sénégalais à 9 chiffres (avec ou sans 221) → « 221XXXXXXXXX », sinon null. */
export function phoneOrNull(raw) {
  let d = String(raw ?? '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.length === 12 && d.startsWith('221')) d = d.slice(3);
  return /^[37]\d{8}$/.test(d) ? '221' + d : null;
}

/** Lit une feuille : repère l'en-tête « N° » et renvoie les lignes de producteurs. */
function readSheet(ws) {
  let headerRow = null;
  for (let r = 1; r <= Math.min(ws.rowCount, 10); r++) {
    if (normalizeHeader(String(cellValue(ws.getRow(r).getCell(1).value) ?? '')) === 'n') {
      headerRow = r;
      break;
    }
  }
  if (!headerRow) return { rows: [], warning: `feuille « ${ws.name} » : en-tête « N° » introuvable, ignorée` };
  const cols = {};
  ws.getRow(headerRow).eachCell((cell, c) => {
    const h = normalizeHeader(String(cellValue(cell.value) ?? ''));
    if (h.includes('prenom')) cols.name ??= c;
    else if (h.includes('telephone')) cols.phone ??= c;
    else if (h.includes('adresse') || h.includes('village')) cols.village ??= c;
    else if (h.includes('valid')) cols.validated ??= c;
    // « SUPERFECIE DECALARE » dans la fiche réelle : on ne se fie pas à l'orthographe.
    else if (/sup[a-z]*f/.test(h) || h.includes('decla') || h.includes('decala')) cols.declared ??= c;
    else if (h.includes('irig') || h.includes('irrig') || h.includes('observation')) (cols.remarks ??= []).push(c);
  });
  if (!cols.name) return { rows: [], warning: `feuille « ${ws.name} » : colonne « nom et prénom » introuvable, ignorée` };
  const rows = [];
  for (let r = headerRow + 1; r <= ws.rowCount; r++) {
    const row = ws.getRow(r);
    const get = (c) => (c ? cellValue(row.getCell(c).value) : null);
    const name = spaces(get(cols.name));
    if (!name || /^TOTAL/.test(fold(name)) || /^TOTAL/.test(fold(get(1)))) continue;
    // Une remarque peut être écrite dans une cellule fusionnée qui recouvre les superficies
    // (« Abandone », « PAS VISITE INJOIGNABLE ») : un texte non numérique y devient une remarque.
    const remarks = (cols.remarks ?? []).map(get);
    const area = (c) => {
      const v = get(c);
      if (typeof v === 'string' && v.trim() && !/^[\d\s.,]+$/.test(v.trim())) {
        remarks.unshift(v);
        return null;
      }
      return v;
    };
    const declared = area(cols.declared);
    const validated = area(cols.validated);
    rows.push({
      sheet: ws.name.trim(),
      line: r,
      name,
      phoneRaw: get(cols.phone),
      villageRaw: get(cols.village),
      declared,
      validated,
      remark: [...new Set(remarks.filter(Boolean).map(spaces))].join(' ; '),
    });
  }
  return { rows };
}

export async function readWorkbook(file) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(file);
  const rows = [];
  const warnings = [];
  wb.eachSheet((ws) => {
    const r = readSheet(ws);
    rows.push(...r.rows);
    if (r.warning) warnings.push(r.warning);
  });
  return { rows, warnings };
}

/** Table de correspondance des villages : Map(village lu replié → village retenu). */
export async function readVillageMap(file) {
  let records;
  if (/\.xlsx$/i.test(file)) {
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.readFile(file);
    const ws = wb.worksheets[0];
    const header = [];
    ws.getRow(1).eachCell((c, i) => (header[i] = normalizeHeader(String(cellValue(c.value) ?? ''))));
    records = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      const o = {};
      header.forEach((h, i) => h && (o[h] = cellValue(ws.getRow(r).getCell(i).value)));
      records.push(o);
    }
  } else records = parseCsv(await readFile(file, 'utf8'));
  const key = (o, start) => Object.keys(o).find((k) => k.startsWith(start));
  const map = new Map();
  for (const o of records) {
    const from = o[key(o, 'village_lu') ?? ''];
    const to = o[key(o, 'village_retenu') ?? ''];
    if (from && spaces(to)) map.set(fold(from), spaces(to).toUpperCase());
  }
  if (!map.size) throw new Error('table des villages : colonnes « Village lu » et « Village retenu » introuvables ou vides');
  return map;
}

/** Applique les règles de la fiche ; renvoie les producteurs à importer et le compte rendu des cas particuliers. */
export function prepare(rows, villageMap) {
  const report = { excluded: [], rejected: [], incompleteNames: [], phonesCleared: [], unknownVillages: new Map(), merges: [], resaisies: [] };
  const groups = new Map();
  for (const r of rows) {
    const where = `${r.sheet} ligne ${r.line}`;
    let declared;
    let validated;
    try {
      declared = number(r.declared, 'superficie déclarée');
      validated = number(r.validated, 'superficie validée');
    } catch (e) {
      report.rejected.push(`${where} : ${e.message}`);
      continue;
    }
    if (!validated && EXCLUDED.some((x) => fold(r.remark).includes(x))) {
      report.excluded.push(`${where} : ${r.remark}`);
      continue;
    }
    const digits = String(r.phoneRaw ?? '').replace(/\D/g, '');
    const key = [fold(r.sheet), digits, fold(r.name)].join('|');
    const list = groups.get(key) ?? [];
    list.push({ ...r, where, declared, validated, digits, key });
    groups.set(key, list);
  }
  const producers = [];
  for (const [key, list] of groups) {
    let kept = list;
    if (list.length > 1) {
      const withValidated = list.filter((x) => x.validated);
      if (withValidated.length <= 1) {
        kept = [withValidated[0] ?? list[0]];
        report.resaisies.push(`${list.map((x) => x.where).join(' + ')} : ressaisie, ${kept[0].where} gardée`);
      } else {
        kept = withValidated;
        report.merges.push(`${withValidated.map((x) => x.where).join(' + ')} : fusionnées, superficies additionnées`);
      }
    }
    const r = kept[0];
    const sum = (k) => (kept.some((x) => x[k] !== null) ? Math.round(kept.reduce((s, x) => s + (x[k] ?? 0), 0) * 10000) / 10000 : null);
    const name = splitName(r.name);
    if (name.incomplete) report.incompleteNames.push(`${r.where} : « ${r.name} »`);
    const phone = phoneOrNull(r.phoneRaw);
    if (!phone) report.phonesCleared.push(`${r.where} : ${r.digits ? `« ${r.digits} » invalide` : 'absent'}`);
    let village = null;
    if (spaces(r.villageRaw)) {
      village = villageMap?.get(fold(r.villageRaw));
      if (!village) {
        village = spaces(r.villageRaw).toUpperCase();
        if (villageMap) report.unknownVillages.set(village, (report.unknownVillages.get(village) ?? 0) + 1);
      }
    }
    producers.push({
      import_key: key,
      where: r.where,
      first_name: name.first,
      last_name: name.last,
      phone,
      village,
      commune: r.sheet,
      area_declared_ha: sum('declared') || null, // 0 déclaré = non renseigné
      area_validated_ha: sum('validated'),
    });
  }
  return { producers, report };
}

export async function importFiche(client, rows, { villageMap = null, simulation = false, log = console.log } = {}) {
  const { producers, report } = prepare(rows, villageMap);
  const stats = { created: 0, updated: 0, unchanged: 0 };
  const missing = [];
  await client.query('begin');
  try {
    for (const p of producers) {
      const found = await client.query(
        'select id, commune, area_declared_ha::float8 as d, area_validated_ha::float8 as v from producers where import_key = $1',
        [p.import_key],
      );
      if (p.village) await client.query('insert into villages (name) values ($1) on conflict do nothing', [p.village]);
      await client.query('insert into communes (name) values ($1) on conflict do nothing', [p.commune]);
      const old = found.rows[0];
      if (!old) {
        await client.query(
          `insert into producers (id, last_name, first_name, phone, village, commune, area_declared_ha, area_validated_ha, import_key, source)
           values ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'import')`,
          [randomUUID(), p.last_name, p.first_name, p.phone, p.village, p.commune, p.area_declared_ha, p.area_validated_ha, p.import_key],
        );
        stats.created++;
      } else if (old.commune !== p.commune || old.d !== p.area_declared_ha || old.v !== p.area_validated_ha) {
        await client.query(
          'update producers set commune = $2, area_declared_ha = $3, area_validated_ha = $4, updated_at = now() where id = $1',
          [old.id, p.commune, p.area_declared_ha, p.area_validated_ha],
        );
        stats.updated++;
      } else stats.unchanged++;
    }
    const keys = producers.map((p) => p.import_key);
    const gone = await client.query(
      `select commune, last_name, first_name from producers
        where import_key is not null and not (import_key = any($1::text[])) order by commune, last_name`,
      [keys],
    );
    for (const g of gone.rows) missing.push(`${g.commune} : ${g.first_name} ${g.last_name}`);
    await client.query(simulation ? 'rollback' : 'commit');
  } catch (e) {
    await client.query('rollback');
    throw e;
  }
  const section = (title, list) => {
    if (!list.length) return;
    log(`${title} (${list.length}) :`);
    for (const x of list) log(`  ${x}`);
  };
  log(simulation ? 'SIMULATION : rien n’a été écrit en base.' : 'Import terminé.');
  log(
    `Producteurs : ${stats.created} créé(s), ${stats.updated} mis à jour, ${stats.unchanged} inchangé(s). ` +
      `Lignes écartées : ${report.excluded.length}. Lignes rejetées : ${report.rejected.length}.`,
  );
  section('Lignes écartées (pas de culture)', report.excluded);
  section('Lignes rejetées', report.rejected);
  section('Fusions (superficies additionnées)', report.merges);
  section('Ressaisies ignorées', report.resaisies);
  section(`Noms « ${NOM_A_COMPLETER} »`, report.incompleteNames);
  section('Importés sans téléphone', report.phonesCleared);
  section('Villages absents de la table de correspondance (gardés tels quels)', [...report.unknownVillages].map(([v, n]) => `${v} (${n})`));
  section('Producteurs en base absents de la fiche (non supprimés)', missing);
  return { ...stats, ...report, missing, producers };
}

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { villages: { type: 'string' }, simulation: { type: 'boolean', default: false } },
  });
  const file = positionals[0];
  if (!file) throw new Error('usage : node scripts/import-fiche-validation.mjs fiche.xlsx --villages correspondance.xlsx [--simulation]');
  const { rows, warnings } = await readWorkbook(file);
  for (const w of warnings) console.log(`Attention : ${w}`);
  const villageMap = values.villages ? await readVillageMap(values.villages) : null;
  if (!villageMap) console.log('Attention : pas de table de correspondance des villages (--villages), les villages sont gardés tels quels.');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await importFiche(client, rows, { villageMap, simulation: values.simulation });
  } finally {
    await client.end();
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
