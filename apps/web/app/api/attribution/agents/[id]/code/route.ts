import { handle, json, uuid } from '@/lib/api';
import { resetSecret } from '@/lib/users';

type Ctx = { params: Promise<{ id: string }> };

/** Nouveau code d'un agent (admin ou coordinateur) : affiché une fois, sessions fermées, journalisé. */
export const POST = handle<Ctx>(
  async (_req, user, { params }) => json(await resetSecret(user, uuid.parse((await params).id), { onlyAgents: true })),
  { can: 'reset_agent_code' },
);
