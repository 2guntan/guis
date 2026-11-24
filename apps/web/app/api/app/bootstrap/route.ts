import { handle, json } from '@/lib/api';
import { query } from '@/lib/db';
import { IRRIGATION, WATER_SOURCES } from '@/lib/labels';

export const dynamic = 'force-dynamic';

/**
 * Tout ce dont l'app a besoin pour travailler hors ligne : listes, producteurs (y compris
 * ceux importés du fichier de distribution), leurs semences et leurs champs.
 * Quelques centaines de producteurs : une seule réponse suffit.
 */
export const GET = handle(async (_req, user) => {
  const [villages, varieties, producers, seeds, fields] = await Promise.all([
    query<{ name: string }>('select name from villages order by name'),
    query<{ name: string }>('select name from varieties order by name'),
    query(`select id, last_name, first_name, phone, member_card, sex, village, photo_id, consent_at, source, updated_at
             from producers order by last_name, first_name`),
    query(`select id, producer_id, variety, quantity_kg::float8 as quantity_kg, to_char(received_on, 'YYYY-MM-DD') as received_on
             from seed_distributions order by received_on nulls last`),
    query(`select id, producer_id, name, contour, area_measured_ha::float8 as area_measured_ha, area_declared_ha::float8 as area_declared_ha,
                  to_char(sown_on, 'YYYY-MM-DD') as sown_on, irrigation, water_source, photo_id, updated_at
             from fields order by created_at`),
  ]);
  return json({
    user,
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
