import { z } from 'zod';
import { body, handle, json } from '@/lib/api';
import { createAccount, listAccounts } from '@/lib/users';

export const dynamic = 'force-dynamic';

const ROLE = z.enum(['admin', 'coordinator', 'agent']);
const Create = z.object({ name: z.string().min(1), phone: z.string().min(6), role: ROLE });

/** Comptes (page « Utilisateurs ») : réservé à l'admin. */
export const GET = handle(async () => json({ users: await listAccounts() }), { can: 'manage_users' });

/** Création : renvoie le secret initial une seule fois (code de 4 chiffres pour un agent). */
export const POST = handle(async (req, user) => json(await createAccount(user, await body(req, Create)), 201), { can: 'manage_users' });
