// Outils des tests de l'API : ils parlent HTTP au serveur Next lancé (GUIS_TEST_URL)
// et lisent la même base PostGIS (DATABASE_URL). Voir apps/web/README.md, « Tests ».
import bcrypt from 'bcryptjs';
import pg from 'pg';

export const BASE = process.env.GUIS_TEST_URL || 'http://localhost:3000';
export const db = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 2 });

export async function resetDb() {
  await db.query(`truncate users, sessions, villages, varieties, communes, agent_communes, producer_distinct, producer_merges, photos, producers, seed_distributions, fields,
                  ndvi_points, field_status, jobs restart identity cascade`);
}

export async function createUser({ phone = '221770000001', name = 'Agent Test', role = 'agent', password = 'motdepasse' } = {}) {
  const r = await db.query('insert into users (phone, name, role, password_hash) values ($1, $2, $3, $4) returning id', [
    phone,
    name,
    role,
    await bcrypt.hash(password, 4),
  ]);
  return { id: r.rows[0].id, phone, name, role, password };
}

export async function api(method, path, { token, body, headers = {} } = {}) {
  const h = { ...headers };
  if (token) h.authorization = `Bearer ${token}`;
  let payload = body;
  if (body !== undefined && !(body instanceof Uint8Array)) {
    h['content-type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  const res = await fetch(BASE + path, { method, headers: h, body: payload });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: res.status, data, res };
}

export async function login(user) {
  const r = await api('POST', '/api/auth/login', { body: { phone: user.phone, password: user.password } });
  if (r.status !== 200) throw new Error(`connexion impossible : ${r.status} ${JSON.stringify(r.data)}`);
  return r.data.token;
}
