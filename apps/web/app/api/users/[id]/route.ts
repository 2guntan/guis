import { z } from 'zod';
import { body, handle, json, uuid } from '@/lib/api';
import { deleteAccount, updateAccount } from '@/lib/users';

const Update = z.object({ name: z.string().optional(), phone: z.string().optional(), role: z.enum(['admin', 'coordinator', 'agent']).optional() });

type Ctx = { params: Promise<{ id: string }> };

/** Modification du nom, du téléphone ou du profil (quitter le profil agent retire les attributions). */
export const PATCH = handle<Ctx>(
  async (req, user, { params }) => json(await updateAccount(user, uuid.parse((await params).id), await body(req, Update))),
  { can: 'manage_users' },
);

/** Suppression d'un compte qui n'a jamais rien fait (409 sinon : le désactiver). */
export const DELETE = handle<Ctx>(async (_req, user, { params }) => json(await deleteAccount(user, uuid.parse((await params).id))), { can: 'manage_users' });
