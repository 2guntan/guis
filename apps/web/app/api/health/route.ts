import { one } from '@/lib/db';

export const dynamic = 'force-dynamic';

/** Santé du service (Docker, Caddy) : répond 200 si la base est joignable. */
export async function GET() {
  try {
    await one('select 1');
    return Response.json({ ok: true });
  } catch {
    return Response.json({ ok: false }, { status: 503 });
  }
}
