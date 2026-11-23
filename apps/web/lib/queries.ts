import 'server-only';
import { query, one } from '@/lib/db';
import type { FieldStatus } from '@/lib/labels';

export type Filters = { q?: string; village?: string; agent?: string; statut?: string; alerte?: string };

export type FieldRow = {
  id: string;
  name: string | null;
  producer_id: string;
  producer_name: string;
  phone: string | null;
  member_card: string | null;
  village: string | null;
  agent_name: string | null;
  area_measured_ha: number | null;
  area_declared_ha: number | null;
  sown_on: string | null;
  irrigation: string | null;
  water_source: string | null;
  status: FieldStatus;
  alerts: { code: string; message: string }[];
  indicative: boolean;
  last_ndvi: number | null;
  geometry: unknown;
  center_lat: number | null;
  center_lng: number | null;
  created_at: string;
};

const FIELD_SELECT = `
  select f.id, f.name, f.producer_id, p.first_name || ' ' || upper(p.last_name) as producer_name, p.phone, p.member_card, p.village,
         u.name as agent_name, f.area_measured_ha::float8 as area_measured_ha, f.area_declared_ha::float8 as area_declared_ha,
         to_char(f.sown_on, 'YYYY-MM-DD') as sown_on, f.irrigation, f.water_source,
         case when f.geom is null then 'none' else coalesce(s.status, 'waiting') end as status,
         coalesce(s.alerts, '[]'::jsonb) as alerts, coalesce(s.indicative, false) as indicative, s.last_ndvi,
         st_asgeojson(f.geom)::jsonb as geometry, st_y(st_centroid(f.geom)) as center_lat, st_x(st_centroid(f.geom)) as center_lng,
         f.created_at
    from fields f
    join producers p on p.id = f.producer_id
    left join users u on u.id = f.created_by
    left join field_status s on s.field_id = f.id`;

/** Clause where des filtres de la liste des champs (gardés dans l'URL). */
function where(f: Filters) {
  const conds: string[] = [];
  const params: unknown[] = [];
  const add = (sql: string, v: unknown) => {
    params.push(v);
    conds.push(sql.replace('?', `$${params.length}`));
  };
  if (f.q?.trim()) {
    add(
      `(unaccent(p.first_name || ' ' || p.last_name || ' ' || coalesce(p.phone, '') || ' ' || coalesce(p.member_card, '') || ' ' || coalesce(f.name, '')) ilike unaccent(?))`,
      `%${f.q.trim().replace(/\s+/g, '%')}%`,
    );
  }
  if (f.village) add('p.village = ?', f.village);
  if (f.agent) add('f.created_by = ?::uuid', f.agent);
  if (f.statut) add(`(case when f.geom is null then 'none' else coalesce(s.status, 'waiting') end) = ?`, f.statut);
  if (f.alerte === '1') conds.push(`jsonb_array_length(coalesce(s.alerts, '[]'::jsonb)) > 0`);
  return { sql: conds.length ? ` where ${conds.join(' and ')}` : '', params };
}

export async function listFields(f: Filters = {}) {
  const w = where(f);
  return query<FieldRow>(`${FIELD_SELECT}${w.sql} order by p.last_name, p.first_name, f.created_at`, w.params);
}

export async function getField(id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  return one<FieldRow & { photo_id: string | null; contour: { accuracy_m?: number }[] }>(
    `${FIELD_SELECT.replace('select f.id,', 'select f.photo_id, f.contour, f.id,')} where f.id = $1`,
    [id],
  );
}

export async function kpis() {
  return (await one<{
    producers: number;
    producers_without_field: number;
    fields: number;
    fields_with_contour: number;
    measured_ha: number;
    declared_ha: number;
    seeds_kg: number;
    alerts: number;
  }>(`select
        (select count(*)::int from producers) as producers,
        (select count(*)::int from producers p where not exists (select 1 from fields f where f.producer_id = p.id)) as producers_without_field,
        (select count(*)::int from fields) as fields,
        (select count(*)::int from fields where geom is not null) as fields_with_contour,
        (select coalesce(sum(area_measured_ha), 0)::float8 from fields) as measured_ha,
        (select coalesce(sum(area_declared_ha), 0)::float8 from fields) as declared_ha,
        (select coalesce(sum(quantity_kg), 0)::float8 from seed_distributions) as seeds_kg,
        (select count(*)::int from field_status where jsonb_array_length(alerts) > 0) as alerts`))!;
}

export async function filterOptions() {
  const [villages, agents] = await Promise.all([
    query<{ name: string }>(`select distinct village as name from producers where village is not null order by 1`),
    query<{ id: string; name: string }>(`select distinct u.id, u.name from users u join fields f on f.created_by = u.id order by u.name`),
  ]);
  return { villages: villages.map((v) => v.name), agents };
}

export type ProducerRow = {
  id: string;
  name: string;
  phone: string | null;
  member_card: string | null;
  sex: string | null;
  village: string | null;
  source: string;
  consent_at: string | null;
  photo_id: string | null;
  agent_name: string | null;
  seeds: { variety: string; quantity_kg: number; received_on: string | null }[];
  fields: { id: string; name: string | null; area_measured_ha: number | null }[];
};

export async function listProducers(q?: string) {
  const params: unknown[] = [];
  let w = '';
  if (q?.trim()) {
    params.push(`%${q.trim().replace(/\s+/g, '%')}%`);
    w = `where unaccent(p.first_name || ' ' || p.last_name || ' ' || coalesce(p.phone, '') || ' ' || coalesce(p.member_card, '') || ' ' || coalesce(p.village, '')) ilike unaccent($1)`;
  }
  return query<ProducerRow>(
    `select p.id, p.first_name || ' ' || upper(p.last_name) as name, p.phone, p.member_card, p.sex, p.village, p.source, p.consent_at, p.photo_id,
            u.name as agent_name,
            coalesce((select jsonb_agg(jsonb_build_object('variety', s.variety, 'quantity_kg', s.quantity_kg::float8, 'received_on', s.received_on) order by s.received_on)
                        from seed_distributions s where s.producer_id = p.id), '[]') as seeds,
            coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'area_measured_ha', f.area_measured_ha::float8) order by f.created_at)
                        from fields f where f.producer_id = p.id), '[]') as fields
       from producers p left join users u on u.id = p.created_by ${w}
      order by p.last_name, p.first_name`,
    params,
  );
}

export async function getProducerSeeds(producerId: string) {
  return query<{ variety: string; quantity_kg: number; received_on: string | null }>(
    `select variety, quantity_kg::float8 as quantity_kg, to_char(received_on, 'YYYY-MM-DD') as received_on from seed_distributions where producer_id = $1 order by received_on`,
    [producerId],
  );
}

export async function getProducer(id: string) {
  return one<{ id: string; photo_id: string | null; consent_at: string | null; sex: string | null }>(
    'select id, photo_id, consent_at, sex from producers where id = $1',
    [id],
  );
}

export async function ndviSeries(fieldId: string) {
  return query<{ date: string; ndvi: number | null; cloud_pct: number | null }>(
    `select to_char(scene_date, 'YYYY-MM-DD') as date, ndvi, cloud_pct from ndvi_points where field_id = $1 order by scene_date`,
    [fieldId],
  );
}
