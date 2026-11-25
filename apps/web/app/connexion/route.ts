import { SESSION_COOKIE, checkPassword, createSession } from '@/lib/auth';
import { redirectTo, safeNext } from '@/lib/redirect';
import { can } from '@/lib/rights';

/** Connexion au tableau de bord (formulaire de /login) : session dans un cookie HTTP-only. */
export async function POST(req: Request) {
  const form = await req.formData();
  const user = await checkPassword(String(form.get('phone') ?? ''), String(form.get('password') ?? ''));
  if (!user) return redirectTo('/login?erreur=identifiants');
  if (!can(user, 'use_dashboard')) return redirectTo('/login?erreur=role');
  const res = redirectTo(safeNext(String(form.get('suite') ?? '')));
  const secure = new URL(req.url).protocol === 'https:' || req.headers.get('x-forwarded-proto') === 'https';
  res.headers.append(
    'Set-Cookie',
    `${SESSION_COOKIE}=${await createSession(user.id)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${60 * 60 * 24 * 30}${secure ? '; Secure' : ''}`,
  );
  return res;
}
