import { deleteSession } from '@/lib/auth';
import { json } from '@/lib/api';

export async function POST(req: Request) {
  const h = req.headers.get('authorization') ?? '';
  if (h.toLowerCase().startsWith('bearer ')) await deleteSession(h.slice(7).trim());
  return json({ ok: true });
}
