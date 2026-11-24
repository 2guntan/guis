import { cookies } from 'next/headers';
import { SESSION_COOKIE, deleteSession } from '@/lib/auth';
import { redirectTo } from '@/lib/redirect';

// Repris de Fieldproof (app/deconnexion/route.ts) : session Guis au lieu de Supabase.
export async function POST() {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (token) await deleteSession(token);
  const res = redirectTo('/login');
  res.headers.append('Set-Cookie', `${SESSION_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`);
  return res;
}
