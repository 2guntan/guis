import 'server-only';
import type { PoolClient } from 'pg';
import { ApiError } from '@/lib/api';
import type { User } from '@/lib/auth';
import { can } from '@/lib/rights';

/**
 * Périmètre d'un compte (ADR-0001) : l'admin et le coordinateur voient tous les producteurs ; un agent, ceux des
 * communes qui lui sont attribuées et ceux qu'il a créés.
 * Fragment SQL sur l'alias `p` de `producers` ; $1 = identifiant du compte, $2 = vrai pour un compte qui voit tout.
 */
export const VISIBLE_PRODUCERS = `($2::boolean
  or p.created_by = $1::uuid
  or p.commune in (select commune from agent_communes where user_id = $1::uuid))`;

export const scopeParams = (user: User) => [user.id, can(user, 'see_all')];

/** Refuse (403, définitif pour l'app) la modification d'un producteur existant hors du périmètre. */
export async function assertCanEdit(c: PoolClient, user: User, producerId: string) {
  if (can(user, 'see_all')) return;
  const r = await c.query<{ visible: boolean }>('select producer_visible($1, $2) as visible from producers where id = $2', [user.id, producerId]);
  if (r.rows[0] && !r.rows[0].visible) throw new ApiError(403, 'Ce producteur n’est pas attribué à votre compte.');
}
