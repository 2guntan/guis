import { handle, json } from '@/lib/api';
import { query } from '@/lib/db';
import { IRRIGATION, WATER_SOURCES } from '@/lib/labels';
import { scopeParams, VISIBLE_PRODUCERS } from '@/lib/scope';

export const dynamic = 'force-dynamic';

/**
 * Tout ce dont l'app a besoin pour travailler hors ligne : listes, producteurs, leurs semences
 * et leurs champs. Un agent ne reçoit que son périmètre (ADR-0001) : producteurs des communes
 * qui lui sont attribuées et ceux qu'il a créés ; l'admin reçoit tout.
 * Quelques centaines de producteurs : une seule réponse suffit.
 */
export const GET = handle(async (_req, user) => {
  const scope = scopeParams(user);
  await query('update users set last_sync_at = now() where id = $1', [user.id]);
  const [villages, varieties, communes, producers, seeds, fields] = await Promise.all([
    query<{ name: string }>('select name from villages order by name'),
    query<{ name: string }>('select name from varieties order by name'),
    query<{ commune: string }>(
      `select name as commune from communes where $2::boolean or name in (select commune from agent_communes where user_id = $1::uuid) order by name`,
      scope,
    ),
    query(
      `select p.id, p.last_name, p.first_name, p.phone, p.member_card, p.sex, p.village, p.commune,
              p.area_declared_ha::float8 as area_declared_ha, p.area_validated_ha::float8 as area_validated_ha,
              p.photo_id, p.consent_at, p.source, p.updated_at
         from producers p where ${VISIBLE_PRODUCERS} order by p.last_name, p.first_name`,
      scope,
    ),
    query(
      `select s.id, s.producer_id, s.variety, s.quantity_kg::float8 as quantity_kg, to_char(s.received_on, 'YYYY-MM-DD') as received_on
         from seed_distributions s join producers p on p.id = s.producer_id where ${VISIBLE_PRODUCERS}
        order by s.received_on nulls last`,
      scope,
    ),
    query(
      `select f.id, f.producer_id, f.name, f.contour, f.area_measured_ha::float8 as area_measured_ha, f.area_declared_ha::float8 as area_declared_ha,
              to_char(f.sown_on, 'YYYY-MM-DD') as sown_on, f.irrigation, f.water_source, f.photo_id, f.updated_at
         from fields f join producers p on p.id = f.producer_id where ${VISIBLE_PRODUCERS} order by f.created_at`,
      scope,
    ),
  ]);
  return json({
    user: { ...user, communes: communes.map((c) => c.commune) },
    lists: {
      villages: villages.map((v) => v.name),
      varieties: varieties.map((v) => v.name),
      irrigation: IRRIGATION,
      water_sources: WATER_SOURCES,
    },
    producers,
    seeds,
    fields,
    server_time: new Date().toISOString(),
  });
});
