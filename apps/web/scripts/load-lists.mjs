// Charge les villages et les variétés depuis des CSV à une colonne « nom » (fichiers gardés hors de git).
//
//   docker compose exec web node scripts/load-lists.mjs --villages /chemin/villages.csv --varietes /chemin/varietes.csv
//   (exemples fictifs : scripts/exemples/)
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import pg from 'pg';
import { parseCsv } from './csv.mjs';

const { values } = parseArgs({ options: { villages: { type: 'string' }, varietes: { type: 'string' } } });

async function load(client, table, file) {
  const rows = parseCsv(await readFile(file, 'utf8'));
  const names = [...new Set(rows.map((r) => r.nom).filter(Boolean))];
  if (!names.length) throw new Error(`${file} : aucune ligne (colonne « nom » attendue)`);
  const r = await client.query(`insert into ${table} (name) select unnest($1::text[]) on conflict do nothing`, [names]);
  console.log(`${table} : ${r.rowCount} ajouté(s), ${names.length - r.rowCount} déjà présent(s)`);
}

async function main() {
  if (!values.villages && !values.varietes) throw new Error('indiquer --villages et/ou --varietes');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    if (values.villages) await load(client, 'villages', values.villages);
    if (values.varietes) await load(client, 'varieties', values.varietes);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
