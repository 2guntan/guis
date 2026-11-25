import 'server-only';
import { ApiError } from '@/lib/api';
import type { User } from '@/lib/auth';
import { query, tx } from '@/lib/db';

/**
 * Attribution des communes aux agents (ADR-0001, spec 2guntan/guis#24) : grille communes × agents,
 * gérée sur le tableau de bord par l'admin et le coordinateur. Un changement arrive sur le
 * téléphone de l'agent à sa synchronisation suivante.
 */
export type Grid = {
  communes: { name: string; producers: number; agents: string[] }[];
  agents: { id: string; name: string; phone: string; last_sync_at: string | null }[];
};

export async function attributionGrid(): Promise<Grid> {
  const [communes, agents] = await Promise.all([
    query<Grid['communes'][number]>(
      `with names as (select name from communes union select distinct commune from producers where commune is not null)
       select n.name,
              (select count(*)::int from producers p where p.commune = n.name) as producers,
              coalesce((select array_agg(ac.user_id::text order by ac.user_id) from agent_communes ac join users u on u.id = ac.user_id
                         where ac.commune = n.name and u.active and u.role = 'agent'), '{}') as agents
         from names n order by n.name`,
    ),
    query<Grid['agents'][number]>(`select id, name, phone, last_sync_at from users where role = 'agent' and active order by name`),
  ]);
  return { communes, agents };
}

export async function setAttribution(_actor: User, commune: string, userId: string, assigned: boolean) {
  await tx(async (c) => {
    const u = (await c.query<{ ok: boolean }>(`select (role = 'agent' and active) as ok from users where id = $1`, [userId])).rows[0];
    if (!u?.ok) throw new ApiError(409, 'Ce compte n’est pas un agent actif.');
    if (assigned) {
      await c.query('insert into communes (name) values ($1) on conflict do nothing', [commune]);
      await c.query('insert into agent_communes (user_id, commune) values ($1, $2) on conflict do nothing', [userId, commune]);
    } else {
      await c.query('delete from agent_communes where user_id = $1 and commune = $2', [userId, commune]);
    }
  });
}
