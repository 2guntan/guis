import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { SESSION_COOKIE, deleteSession } from '@/lib/auth';

// Repris de Fieldproof (app/deconnexion/route.ts) : session Guis au lieu de Supabase.
export async function POST(req: Request) {
  const jar = await cookies();
  const token = jar.get(SESSION_COOKIE)?.value;
  if (token) await deleteSession(token);
  const res = NextResponse.redirect(new URL('/login', req.url), { status: 303 });
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
