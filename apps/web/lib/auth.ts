import 'server-only';
import { createHash, randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { one, query } from '@/lib/db';
import { normalizePhone } from '@/lib/phone';
import { can, type Action } from '@/lib/rights';

export type User = { id: string; phone: string; name: string; role: 'admin' | 'coordinator' | 'agent' };

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

export const MAX_FAILURES = 5;
const BLOCK_MINUTES = 15;
export const BLOCKED_MESSAGE = 'Trop d’essais. Réessayez dans 15 minutes ou appelez votre coordinateur.';

/**
 * Connexion protégée contre les essais répétés (ADR-0003) : après 5 échecs consécutifs pour un même
 * téléphone, toute tentative est refusée pendant 15 minutes, même avec le bon secret. Le compteur
 * vaut aussi pour un téléphone sans compte, pour ne pas révéler quels numéros en ont un.
 */
export async function attemptLogin(phone: string, secret: string): Promise<{ user: User } | { blocked: true } | null> {
  const key = normalizePhone(phone);
  const state = await one<{ blocked: boolean }>(
    'select coalesce(blocked_until > now(), false) as blocked from login_attempts where phone = $1',
    [key],
  );
  if (state?.blocked) return { blocked: true };
  const user = await checkPassword(phone, secret);
  if (user) {
    await query('delete from login_attempts where phone = $1', [key]);
    return { user };
  }
  const r = await one<{ failures: number }>(
    `insert into login_attempts (phone, failures) values ($1, 1)
     on conflict (phone) do update set
       failures = case when login_attempts.blocked_until is not null then 1 else login_attempts.failures + 1 end,
       blocked_until = null, updated_at = now()
     returning failures`,
    [key],
  );
  if (r && r.failures >= MAX_FAILURES) {
    await query(`update login_attempts set blocked_until = now() + make_interval(mins => $2), failures = 0 where phone = $1`, [key, BLOCK_MINUTES]);
    return { blocked: true };
  }
  return null;
}

/** Lève le blocage d'un téléphone (réinitialisation du secret par l'admin ou le coordinateur). */
export async function clearLoginAttempts(phone: string) {
  await query('delete from login_attempts where phone = $1', [normalizePhone(phone)]);
}

/** Ouvre une session et renvoie le jeton (gardé par l'app Android ou dans un cookie). */
export async function createSession(userId: string): Promise<string> {
  const token = randomBytes(32).toString('base64url');
  await query('delete from sessions where expires_at < now()');
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

/** Pages du tableau de bord : comptes qui peuvent le consulter (admin, coordinateur), et au besoin un droit précis. */
export async function requireDashboard(action: Action = 'use_dashboard'): Promise<User> {
  const user = await userFromToken((await cookies()).get(SESSION_COOKIE)?.value);
  if (!user) redirect('/login');
  if (!can(user, 'use_dashboard')) redirect('/login?refus=1');
  if (!can(user, action)) redirect('/');
  return user;
}
