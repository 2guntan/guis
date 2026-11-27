import type { PoolClient } from 'pg';
import { ApiError } from '@/lib/api';

/**
 * Modification concurrente (ADR-0004) : l'app envoie `base_edited_at`, la date de dernière modification
 * qu'elle a reçue. Si quelqu'un d'autre a modifié la fiche depuis, l'envoi est refusé (409) et l'agent
 * choisit sur le téléphone. Sans `base_edited_at` (ancienne app, ou « Renvoyer » après un conflit),
 * l'envoi remplace la version du serveur. Les envois successifs du même agent ne se gênent jamais.
 */
export async function assertNotEditedElsewhere(
  c: PoolClient,
  table: 'producers' | 'fields',
  id: string,
  userId: string,
  base: string | null | undefined,
  what: string,
) {
  if (base === undefined) return;
  const r = await c.query<{ conflict: boolean }>(
    `select edited_at is not null and edited_by is distinct from $2::uuid
            and ($3::timestamptz is null or date_trunc('milliseconds', edited_at) > $3::timestamptz) as conflict
       from ${table} where id = $1 for update`,
    [id, userId, base],
  );
  if (r.rows[0]?.conflict) {
    throw new ApiError(
      409,
      `${what} a été modifié par quelqu’un d’autre depuis votre dernier chargement. « Renvoyer » remplace sa version par la vôtre ; « Écarter » garde la sienne.`,
    );
  }
}
