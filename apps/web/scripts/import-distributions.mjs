// Importe le fichier de distribution des semences de la coopérative (CSV gardé hors de git).
// Crée les producteurs (source « import », consentement à recueillir par l'agent) et leurs lignes de semence.
// Idempotent : relancer l'import sur le même fichier ne crée rien de plus.
//
//   docker compose exec web node scripts/import-distributions.mjs /chemin/distributions.csv
//
// Colonnes (en-tête obligatoire, ordre libre, accents et casse indifférents ; séparateur « ; » ou « , ») :
//   nom ; prenom ; telephone ; carte_membre ; sexe (F/H) ; village ; variete ; quantite_kg ; date_reception (JJ/MM/AAAA ou AAAA-MM-JJ)
// Un producteur est reconnu par sa carte de membre, sinon par son téléphone et son nom.
// Exemple fictif : scripts/exemples/distributions.csv
import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import { parseCsv } from './csv.mjs';
import { normalizePhone } from './phone.mjs';

const fold = (s) => (s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toUpperCase();

/** UUID déterministe (format v4) : la même ligne de semence garde le même identifiant d'un import à l'autre. */
function stableId(...parts) {
  const h = createHash('sha256').update(parts.join('|')).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-${((parseInt(h[16], 16) & 3) | 8).toString(16)}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

function parseDate(v) {
  if (!v) return null;
  let m = v.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  m = v.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return v;
  throw new Error(`date illisible « ${v} »`);
}

/** Vérifie et met en forme une ligne ; lève une erreur lisible sinon. */
export function readRow(r) {
  const last = (r.nom ?? '').trim();
  const first = (r.prenom ?? '').trim();
  if (!last || !first) throw new Error('nom et prénom obligatoires');
  const sex = fold(r.sexe).charAt(0);
  if (sex && !['F', 'H'].includes(sex)) throw new Error(`sexe « ${r.sexe} » (F ou H attendu)`);
  const phone = r.telephone ? normalizePhone(r.telephone) : null;
  if (phone && !/^[0-9]{9,15}$/.test(phone)) throw new Error(`téléphone « ${r.telephone} » invalide`);
  const variety = (r.variete ?? '').trim();
  const kg = r.quantite_kg ? Number(String(r.quantite_kg).replace(',', '.').replace(/\s/g, '')) : null;
  if (variety && !(kg > 0)) throw new Error(`quantité « ${r.quantite_kg ?? ''} » invalide`);
  return {
    last_name: last,
    first_name: first,
    phone,
    member_card: (r.carte_membre ?? '').trim() || null,
    sex: sex || null,
    village: (r.village ?? '').trim() || null,
    variety: variety || null,
    quantity_kg: variety ? kg : null,
    received_on: parseDate((r.date_reception ?? '').trim()),
  };
}

export async function importDistributions(client, rows, log = console.log) {
  const stats = { producersCreated: 0, producersFound: 0, seedsCreated: 0, seedsExisting: 0, rejected: [] };
  const seen = new Map(); // producteurs déjà traités dans ce fichier
  await client.query('begin');
  try {
    for (const raw of rows) {
      let row;
      try {
        row = readRow(raw);
      } catch (e) {
        stats.rejected.push({ line: raw._line, reason: e.message });
        continue;
      }
      const key = row.member_card ? `card:${fold(row.member_card)}` : `phone:${row.phone ?? ''}:${fold(row.last_name)}:${fold(row.first_name)}`;
      let id = seen.get(key);
      if (!id) {
        const found = row.member_card
          ? await client.query('select id from producers where upper(member_card) = upper($1)', [row.member_card])
          : await client.query(
              `select id from producers where coalesce(phone, '') = coalesce($1, '') and upper(unaccent(last_name)) = $2 and upper(unaccent(first_name)) = $3`,
              [row.phone, fold(row.last_name), fold(row.first_name)],
            );
        if (found.rows[0]) {
          id = found.rows[0].id;
          stats.producersFound++;
        } else {
          id = randomUUID();
          await client.query(
            `insert into producers (id, last_name, first_name, phone, member_card, sex, village, source) values ($1, $2, $3, $4, $5, $6, $7, 'import')`,
            [id, row.last_name, row.first_name, row.phone, row.member_card, row.sex, row.village],
          );
          if (row.village) await client.query('insert into villages (name) values ($1) on conflict do nothing', [row.village]);
          stats.producersCreated++;
        }
        seen.set(key, id);
      }
      if (row.variety) {
        await client.query('insert into varieties (name) values ($1) on conflict do nothing', [row.variety]);
        const seedId = stableId(id, fold(row.variety), row.quantity_kg, row.received_on ?? '');
        const r = await client.query(
          `insert into seed_distributions (id, producer_id, variety, quantity_kg, received_on) values ($1, $2, $3, $4, $5) on conflict (id) do nothing`,
          [seedId, id, row.variety, row.quantity_kg, row.received_on],
        );
        if (r.rowCount) stats.seedsCreated++;
        else stats.seedsExisting++;
      }
    }
    await client.query('commit');
  } catch (e) {
    await client.query('rollback');
    throw e;
  }
  log(
    `Producteurs : ${stats.producersCreated} créé(s), ${stats.producersFound} retrouvé(s). ` +
      `Semences : ${stats.seedsCreated} ligne(s) créée(s), ${stats.seedsExisting} déjà présente(s). ` +
      `Lignes rejetées : ${stats.rejected.length}.`,
  );
  for (const r of stats.rejected) log(`  ligne ${r.line} : ${r.reason}`);
  return stats;
}

async function main() {
  const file = process.argv[2];
  if (!file) throw new Error('usage : node scripts/import-distributions.mjs fichier.csv');
  const rows = parseCsv(await readFile(file, 'utf8'));
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await importDistributions(client, rows);
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
