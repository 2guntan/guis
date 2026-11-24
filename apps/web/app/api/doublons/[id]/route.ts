import { userFromRequest } from '@/lib/auth';
import { tx } from '@/lib/db';
import { markDistinct, merge } from '@/lib/duplicates';
import { redirectTo } from '@/lib/redirect';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Décision de l'admin sur un doublon possible (formulaire de /doublons) : `action=distinct` ou `action=merge&into=<id>`. */
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const user = await userFromRequest(req);
  if (!user) return redirectTo('/login');
  if (user.role !== 'admin') return redirectTo('/login?refus=1');
  const id = (await params).id;
  const form = await req.formData();
  const action = String(form.get('action') ?? '');
  const into = String(form.get('into') ?? '');
  if (!UUID.test(id) || (action === 'merge' && !UUID.test(into))) return redirectTo('/doublons?erreur=1');
  let ok = true;
  await tx(async (c) => {
    if (action === 'distinct') await markDistinct(c, id, user.id);
    else if (action === 'merge') ok = await merge(c, id, into, user.id);
    else ok = false;
  });
  return redirectTo(ok ? `/doublons?fait=${action}` : '/doublons?erreur=1');
}
