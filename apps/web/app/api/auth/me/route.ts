import { handle, json } from '@/lib/api';

export const dynamic = 'force-dynamic';

/** Le compte du jeton (l'app vérifie sa session au démarrage). */
export const GET = handle(async (_req, user) => json({ user }));
