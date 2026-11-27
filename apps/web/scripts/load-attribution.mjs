// Charge l'attribution des communes aux agents (ADR-0001) depuis un fichier gardé hors de git.
//
//   docker compose exec web node scripts/load-attribution.mjs /tmp/communes-agents.xlsx
//
// Classeur (première feuille) ou CSV, une ligne par couple commune / agent :
//   commune ; nom de l'agent ; téléphone de l'agent (connexion)
// Une commune peut avoir plusieurs agents, un agent plusieurs communes (même téléphone sur plusieurs lignes).
// L'attribution existante est remplacée en entier. Un agent inconnu est créé, avec un code de 4 chiffres
// initial affiché une seule fois, à lui transmettre. Exemple fictif : scripts/exemples/communes-agents.csv
import { readFile } from 'node:fs/promises';
import bcrypt from 'bcryptjs';
import ExcelJS from 'exceljs';
import pg from 'pg';
import { normalizeHeader, parseCsv } from './csv.mjs';
import { normalizePhone } from './phone.mjs';
import { generateCode } from './secrets.mjs';

const spaces = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();

async function readRows(file) {
  if (!/\.xlsx$/i.test(file)) return parseCsv(await readFile(file, 'utf8'));
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(file);
  const ws = wb.worksheets[0];
  const val = (v) => (v && typeof v === 'object' && 'result' in v ? v.result : v && typeof v === 'object' && 'text' in v ? v.text : v);
  const header = [];
  ws.getRow(1).eachCell((c, i) => (header[i] = normalizeHeader(String(val(c.value) ?? ''))));
  const rows = [];
  for (let r = 2; r <= ws.rowCount; r++) {
    const o = { _line: r };
    header.forEach((h, i) => h && (o[h] = spaces(val(ws.getRow(r).getCell(i).value))));
    rows.push(o);
  }
  return rows;
}


export async function loadAttribution(client, rows, { log = console.log, password = generateCode } = {}) {
  const pick = (o, ...starts) => o[Object.keys(o).find((k) => starts.some((s) => k.startsWith(s))) ?? ''] ?? '';
  const pairs = [];
  const warnings = [];
  for (const o of rows) {
    const commune = spaces(pick(o, 'commune')).toUpperCase();
    const rawPhone = spaces(pick(o, 'telephone', 'tel'));
    const name = spaces(pick(o, 'nom'));
    if (!commune && !rawPhone) continue;
    if (!commune) {
      warnings.push(`ligne ${o._line} : commune manquante, ignorée`);
      continue;
    }
    if (!rawPhone) {
      warnings.push(`ligne ${o._line} : ${commune} sans agent, ignorée`);
      continue;
    }
    const phone = normalizePhone(rawPhone);
    if (!/^221[37]\d{8}$/.test(phone)) {
      warnings.push(`ligne ${o._line} : téléphone « ${rawPhone} » invalide, ignorée`);
      continue;
    }
    pairs.push({ commune, phone, name });
  }
  const created = [];
  await client.query('begin');
  try {
    await client.query('delete from agent_communes');
    const ids = new Map();
    for (const p of pairs) {
      let id = ids.get(p.phone);
      if (!id) {
        const u = await client.query('select id, role, name from users where phone = $1', [p.phone]);
        if (u.rows[0]) {
          id = u.rows[0].id;
          if (u.rows[0].role !== 'agent') warnings.push(`${p.phone} (${u.rows[0].name}) est ${u.rows[0].role} : il voit déjà tout`);
        } else {
          const pw = password(p.phone);
          const r = await client.query(
            `insert into users (phone, name, role, password_hash) values ($1, $2, 'agent', $3) returning id`,
            [p.phone, p.name || `Agent ${p.phone.slice(-4)}`, await bcrypt.hash(pw, 10)],
          );
          id = r.rows[0].id;
          created.push({ phone: p.phone, name: p.name, password: pw });
        }
        ids.set(p.phone, id);
      }
      await client.query('insert into communes (name) values ($1) on conflict do nothing', [p.commune]);
      await client.query('insert into agent_communes (user_id, commune) values ($1, $2) on conflict do nothing', [id, p.commune]);
    }
    await client.query('commit');
  } catch (e) {
    await client.query('rollback');
    throw e;
  }
  const summary = await client.query(
    `select c.name as commune, count(a.user_id)::int as agents,
            (select count(*)::int from producers p where p.commune = c.name) as producteurs
       from communes c left join agent_communes a on a.commune = c.name group by c.name order by c.name`,
  );
  log(`Attribution chargée : ${pairs.length} ligne(s), ${ids_count(pairs)} agent(s), ${created.length} compte(s) créé(s).`);
  for (const s of summary.rows) log(`  ${s.commune} : ${s.agents} agent(s), ${s.producteurs} producteur(s)${s.agents ? '' : ' — AUCUN AGENT'}`);
  for (const w of warnings) log(`Attention : ${w}`);
  if (created.length) {
    log('Comptes créés — code initial (4 chiffres) à transmettre à chaque agent (affiché une seule fois) :');
    for (const c of created) log(`  ${c.phone} ${c.name} : ${c.password}`);
  }
  return { pairs, created, warnings, summary: summary.rows };
}

const ids_count = (pairs) => new Set(pairs.map((p) => p.phone)).size;

async function main() {
  const file = process.argv[2];
  if (!file) throw new Error('usage : node scripts/load-attribution.mjs communes-agents.xlsx');
  const rows = await readRows(file);
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await loadAttribution(client, rows);
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
