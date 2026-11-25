import { z } from 'zod';
import { body, handle, json, uuid } from '@/lib/api';
import { attributionGrid, setAttribution } from '@/lib/attribution';

export const dynamic = 'force-dynamic';

const Cell = z.object({ commune: z.string().min(1), user_id: uuid, assigned: z.boolean() });

/** Grille communes × agents : admin et coordinateur. */
export const GET = handle(async () => json(await attributionGrid()), { can: 'manage_attribution' });

/** Coche (`assigned: true`) ou décoche une commune pour un agent. */
export const PUT = handle(async (req, user) => {
  const c = await body(req, Cell);
  await setAttribution(user, c.commune.trim(), c.user_id, c.assigned);
  return json({ ok: true });
}, { can: 'manage_attribution' });
