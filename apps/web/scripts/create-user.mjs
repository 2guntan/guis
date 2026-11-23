// Crée ou met à jour un compte. Le mot de passe est lu sur l'entrée standard ou dans GUIS_PASSWORD,
// jamais en argument (il resterait dans l'historique du shell).
//
//   docker compose exec -it web node scripts/create-user.mjs --phone "77 123 45 67" --name "Awa Diop" --role agent
import bcrypt from 'bcryptjs';
import pg from 'pg';
import { createInterface } from 'node:readline/promises';
import { parseArgs } from 'node:util';
import { normalizePhone } from './phone.mjs';

const { values } = parseArgs({
  options: { phone: { type: 'string' }, name: { type: 'string' }, role: { type: 'string', default: 'agent' } },
});

async function readPassword() {
  if (process.env.GUIS_PASSWORD) return process.env.GUIS_PASSWORD;
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  const p = await rl.question('Mot de passe (8 caractères au moins) : ');
  rl.close();
  return p;
}

async function main() {
  const phone = normalizePhone(values.phone);
  if (!/^[0-9]{6,15}$/.test(phone)) throw new Error('--phone : numéro invalide');
  if (!values.name?.trim()) throw new Error('--name est obligatoire');
  if (!['admin', 'agent'].includes(values.role)) throw new Error('--role : admin ou agent');
  const password = await readPassword();
  if (password.length < 8) throw new Error('mot de passe trop court (8 caractères au moins)');
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const r = await client.query(
      `insert into users (phone, name, role, password_hash) values ($1, $2, $3, $4)
       on conflict (phone) do update set name = excluded.name, role = excluded.role, password_hash = excluded.password_hash, active = true
       returning (xmax = 0) as created`,
      [phone, values.name.trim(), values.role, await bcrypt.hash(password, 10)],
    );
    console.log(`${r.rows[0].created ? 'Compte créé' : 'Compte mis à jour'} : ${phone} (${values.role})`);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
