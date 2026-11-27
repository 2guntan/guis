import { handle, json, uuid } from '@/lib/api';
import { resetSecret } from '@/lib/users';

type Ctx = { params: Promise<{ id: string }> };

/** Réinitialisation par l'admin : nouveau secret (affiché une fois), sessions fermées, blocage levé. */
export const POST = handle<Ctx>(async (_req, user, { params }) => json(await resetSecret(user, uuid.parse((await params).id))), { can: 'manage_users' });
