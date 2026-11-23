import 'server-only';
import { createHash, randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { one, query } from '@/lib/db';
import { normalizePhone } from '@/lib/phone';

export type User = { id: string; phone: string; name: string; role: 'admin' | 'agent' };

export const SESSION_COOKIE = 'guis_session';
const SESSION_DAYS = 90;

const hash = (token: string) => createHash('sha256').update(token).digest('hex');

/** Vérifie le téléphone et le mot de passe ; renvoie le compte ou null. */
export async function checkPassword(phone: string, password: string): Promise<User | null> {
  const row = await one<User & { password_hash: string }>(
    'select id, phone, name, role, password_hash from users where phone = $1 and active',
    [normalizePhone(phone)],
  );
  if (!row || !(await bcrypt.compare(password, row.password_hash))) return null;
  return { id: row.id, phone: row.phone, name: row.name, role: row.role };
}

/** Ouvre une session et renvoie le jeton (gardé par l'app Android ou dans un cookie). */
export async function createSession(userId: string): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  await query(`insert into sessions (token_hash, user_id, expires_at) values ($1, $2, now() + make_interval(days => $3))`, [
    hash(token),
    userId,
    SESSION_DAYS,
  ]);
  return token;
}

export async function deleteSession(token: string) {
  await query('delete from sessions where token_hash = $1', [hash(token)]);
}

export async function userFromToken(token: string | null | undefined): Promise<User | null> {
  if (!token) return null;
  return one<User>(
    `select u.id, u.phone, u.name, u.role from sessions s join users u on u.id = s.user_id
      where s.token_hash = $1 and s.expires_at > now() and u.active`,
    [hash(token)],
  );
}

/** Le compte d'une requête de l'API : en-tête `Authorization: Bearer`, sinon le cookie du tableau de bord. */
export async function userFromRequest(req: Request): Promise<User | null> {
  const h = req.headers.get('authorization') ?? '';
  const bearer = h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : null;
  if (bearer) return userFromToken(bearer);
  const c = (await cookies()).get(SESSION_COOKIE)?.value;
  return userFromToken(c);
}

/** Pages du tableau de bord : réservées aux comptes `admin`. */
export async function requireAdmin(): Promise<User> {
  const user = await userFromToken((await cookies()).get(SESSION_COOKIE)?.value);
  if (!user) redirect('/login');
  if (user.role !== 'admin') redirect('/login?refus=1');
  return user;
}
