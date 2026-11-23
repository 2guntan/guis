import { NextResponse } from 'next/server';
import { SESSION_COOKIE, checkPassword, createSession } from '@/lib/auth';

const redirectTo = (req: Request, path: string) => NextResponse.redirect(new URL(path, req.url), { status: 303 });

/** Connexion au tableau de bord (formulaire de /login) : session dans un cookie HTTP-only. */
export async function POST(req: Request) {
  const form = await req.formData();
  const user = await checkPassword(String(form.get('phone') ?? ''), String(form.get('password') ?? ''));
  if (!user) return redirectTo(req, '/login?erreur=identifiants');
  if (user.role !== 'admin') return redirectTo(req, '/login?erreur=role');
  const suite = String(form.get('suite') ?? '');
  const res = redirectTo(req, suite.startsWith('/') && !suite.startsWith('//') ? suite : '/');
  res.cookies.set(SESSION_COOKIE, await createSession(user.id), {
    httpOnly: true,
    sameSite: 'lax',
    secure: new URL(req.url).protocol === 'https:' || req.headers.get('x-forwarded-proto') === 'https',
    path: '/',
    maxAge: 60 * 60 * 24 * 30,
  });
  return res;
}
