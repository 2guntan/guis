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

/**
 * Photos liées à une fiche (audit L12) : une photo déposée par un autre compte ne peut pas être
 * rattachée par un agent (identifiant deviné ou recopié). Une photo déjà liée à la fiche reste
 * acceptée telle quelle ; l'admin peut tout rattacher ; une photo pas encore déposée passe.
 */
export async function assertOwnPhoto(
  c: PoolClient,
  table: 'producers' | 'fields',
  id: string,
  user: { id: string; role: string },
  photoIds: string | string[] | null | undefined,
) {
  const ids = (Array.isArray(photoIds) ? photoIds : [photoIds]).filter((x): x is string => !!x);
  if (ids.length === 0 || user.role === 'admin') return;
  const linked = table === 'producers' ? 'array_remove(array[photo_id], null)' : 'photo_ids';
  const r = await c.query<{ foreign: boolean }>(
    `select bool_or(ph.uploaded_by is not null and ph.uploaded_by <> $3::uuid) as foreign
       from photos ph
      where ph.id = any($1::uuid[])
        and not ph.id = any(coalesce((select ${linked} from ${table} where id = $2), '{}'::uuid[]))`,
    [ids, id, user.id],
  );
  if (r.rows[0]?.foreign) throw new ApiError(403, 'Cette photo a été déposée par un autre compte.');
}
