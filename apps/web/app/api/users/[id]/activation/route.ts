import { z } from 'zod';
import { body, handle, json, uuid } from '@/lib/api';
import { deactivateAccount, reactivateAccount } from '@/lib/users';

type Ctx = { params: Promise<{ id: string }> };
const Activation = z.object({ active: z.boolean() });

/** Désactiver (`active: false`) ou réactiver (`active: true`) un compte. */
export const PUT = handle<Ctx>(async (req, user, { params }) => {
  const id = uuid.parse((await params).id);
  const { active } = await body(req, Activation);
  return json(active ? await reactivateAccount(user, id) : await deactivateAccount(user, id));
}, { can: 'manage_users' });
