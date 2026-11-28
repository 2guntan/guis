// Applique les migrations SQL de db/migrations dans l'ordre, une seule fois chacune.
// Lancé au démarrage du conteneur web ; à la main : DATABASE_URL=… node scripts/migrate.mjs
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import pg from 'pg';

const dir = process.env.MIGRATIONS_DIR || path.resolve(import.meta.dirname, '../../../db/migrations');

export async function migrate(connectionString = process.env.DATABASE_URL, log = console.log) {
  // La base peut démarrer après le web : on réessaie quelques secondes. Un client pg ne se
  // reconnecte pas après un échec (« Client has already been connected ») : un nouveau à chaque essai.
  let client;
  for (let i = 0; ; i++) {
    client = new pg.Client({ connectionString });
    try {
      await client.connect();
      break;
    } catch (e) {
      await client.end().catch(() => {});
      if (i >= 30) throw e;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  try {
    await client.query('select pg_advisory_lock(424242)');
    await client.query('create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())');
    const done = new Set((await client.query('select name from schema_migrations')).rows.map((r) => r.name));
    const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
    for (const f of files) {
      if (done.has(f)) continue;
      const sql = await readFile(path.join(dir, f), 'utf8');
      await client.query('begin');
      try {
        await client.query(sql);
        await client.query('insert into schema_migrations (name) values ($1)', [f]);
        await client.query('commit');
        log(`migration appliquée : ${f}`);
      } catch (e) {
        await client.query('rollback');
        throw new Error(`migration ${f} : ${e.message}`);
      }
    }
  } finally {
    await client.end();
  }
}

// Lancé directement (`node scripts/x.mjs`), pas importé par un test. pathToFileURL encode le chemin
// (« 1. PROJECTS » → « 1.%20PROJECTS ») comme import.meta.url : la comparaison marche avec des espaces.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  migrate().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
