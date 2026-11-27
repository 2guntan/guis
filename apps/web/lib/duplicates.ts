import 'server-only';
import type { PoolClient } from 'pg';
import { query } from '@/lib/db';

export type DuplicateSide = {
  id: string;
  name: string;
  phone: string | null;
  member_card: string | null;
  village: string | null;
  commune: string | null;
  source: string;
  agent_name: string | null;
  created_at: string;
  fields: number;
  seeds: number;
};

const SIDE = `select p.id, p.first_name || ' ' || upper(p.last_name) as name, p.phone, p.member_card, p.village, p.commune, p.source,
                     u.name as agent_name, to_char(p.created_at, 'YYYY-MM-DD') as created_at,
                     (select count(*)::int from fields f where f.producer_id = p.id) as fields,
                     (select count(*)::int from seed_distributions s where s.producer_id = p.id) as seeds
                from producers p left join users u on u.id = p.created_by`;

/** Producteurs marqués doublon possible, chacun avec les producteurs existants qui partagent son téléphone. */
export async function listDuplicates() {
  const news = await query<DuplicateSide & { candidates: string[] }>(
    `${SIDE.replace('u.name as agent_name,', 'p.possible_duplicate_of as candidates, u.name as agent_name,')} where p.possible_duplicate_of is not null order by p.created_at`,
  );
  const ids = [...new Set(news.flatMap((n) => n.candidates))];
  const others = ids.length ? await query<DuplicateSide>(`${SIDE} where p.id = any($1::uuid[])`, [ids]) : [];
  const byId = new Map(others.map((o) => [o.id, o]));
  return news.map((n) => ({ ...n, candidates: n.candidates.map((id) => byId.get(id)).filter((x): x is DuplicateSide => !!x) }));
}

export async function countDuplicates() {
  return (await query<{ n: number }>('select count(*)::int as n from producers where possible_duplicate_of is not null'))[0].n;
}

/** « Ce sont deux personnes » : le marquage disparaît et ces couples ne seront plus signalés. */
export async function markDistinct(c: PoolClient, id: string, adminId: string) {
  const r = await c.query<{ candidates: string[] | null }>('select possible_duplicate_of as candidates from producers where id = $1 for update', [id]);
  for (const o of r.rows[0]?.candidates ?? []) {
    await c.query(
      `insert into producer_distinct (a, b, decided_by) values (least($1::uuid, $2::uuid), greatest($1::uuid, $2::uuid), $3) on conflict do nothing`,
      [id, o, adminId],
    );
  }
  await c.query('update producers set possible_duplicate_of = null where id = $1', [id]);
}

/**
 * Fusion : les champs, remises et photos du producteur saisi passent sur le producteur existant,
 * qui garde ses propres données et ne complète que ce qui lui manque. Le producteur saisi est supprimé.
 */
export async function merge(c: PoolClient, id: string, into: string, adminId: string) {
  const r = await c.query<{ ok: boolean }>(
    'select $2::uuid = any(possible_duplicate_of) as ok from producers where id = $1 for update',
    [id, into],
  );
  if (!r.rows[0]?.ok) return false;
  await c.query('update fields set producer_id = $2, updated_at = now() where producer_id = $1', [id, into]);
  await c.query('update seed_distributions set producer_id = $2, updated_at = now() where producer_id = $1', [id, into]);
  const old = (await c.query('select * from producers where id = $1', [id])).rows[0];
  await c.query('update producers set member_card = null where id = $1', [id]); // libère la carte (unique)
  await c.query(
    `update producers set
        phone = coalesce(phone, $2), member_card = coalesce(nullif(member_card, ''), $3), sex = coalesce(sex, $4),
        village = coalesce(village, $5), photo_id = coalesce(photo_id, $6),
        consent_at = coalesce(consent_at, $7), consent_by = case when consent_at is null then $8 else consent_by end,
        updated_at = now(), edited_at = now(), edited_by = null
      where id = $1`,
    [into, old.phone, old.member_card, old.sex, old.village, old.photo_id, old.consent_at, old.consent_by],
  );
  await c.query('update producer_merges set new_id = $2 where new_id = $1', [id, into]);
  await c.query(
    `update producers set possible_duplicate_of = nullif(array_remove(array_replace(possible_duplicate_of, $1::uuid, $2::uuid), id), '{}')
      where $1::uuid = any(possible_duplicate_of)`,
    [id, into],
  );
  await c.query('insert into producer_merges (old_id, new_id, merged_by) values ($1, $2, $3)', [id, into, adminId]);
  await c.query('delete from producers where id = $1', [id]);
  return true;
}
