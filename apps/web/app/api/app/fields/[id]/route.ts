import { z } from 'zod';
import { ApiError, body, handle, json, uuid } from '@/lib/api';
import { tx } from '@/lib/db';

const opt = z.string().trim().max(100).nullish().transform((v) => (v ? v : null));

const Point = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracy_m: z.number().nonnegative().nullish(),
  captured_at: z.string().nullish(),
});

const Field = z.object({
  producer_id: uuid,
  name: opt,
  contour: z.array(Point).max(2000).default([]),
  area_declared_ha: z.number().positive().max(1000).nullish(),
  sown_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullish(),
  irrigation: opt,
  water_source: opt,
  photo_id: uuid.nullish(),
});

/** Polygone GeoJSON fermé ([lng, lat]) à partir des sommets relevés, ou null sous 3 sommets. */
function polygon(points: { lat: number; lng: number }[]) {
  if (points.length < 3) return null;
  const ring = points.map((p) => [p.lng, p.lat]);
  ring.push([points[0].lng, points[0].lat]);
  return { type: 'Polygon', coordinates: [ring] };
}

/** Enregistre un champ (création ou mise à jour, par identifiant). Un nouveau contour lance le calcul satellite. */
export const PUT = handle<{ params: Promise<{ id: string }> }>(async (req, user, { params }) => {
  const id = uuid.parse((await params).id);
  const f = await body(req, Field);
  const geom = polygon(f.contour);
  await tx(async (c) => {
    if (geom) {
      const v = await c.query<{ ok: boolean; reason: string; m2: number }>(
        `select st_isvalid(g) as ok, st_isvalidreason(g) as reason, st_area(g::geography) as m2
           from (select st_setsrid(st_geomfromgeojson($1), 4326) as g) x`,
        [JSON.stringify(geom)],
      );
      if (!v.rows[0].ok) throw new ApiError(422, 'Le contour se croise : reprenez le tour du champ dans l’ordre.');
      if (v.rows[0].m2 < 100) throw new ApiError(422, 'Le contour fait moins de 100 m² : reprenez le tour du champ.');
    }
    const r = await c.query(
      `insert into fields (id, producer_id, name, geom, contour, area_declared_ha, sown_on, irrigation, water_source, photo_id, created_by)
       values ($1, $2, $3, case when $4::text is null then null else st_setsrid(st_geomfromgeojson($4), 4326) end, $5, $6, $7, $8, $9, $10, $11)
       on conflict (id) do update set name = excluded.name, geom = excluded.geom, contour = excluded.contour,
         area_declared_ha = excluded.area_declared_ha, sown_on = excluded.sown_on, irrigation = excluded.irrigation,
         water_source = excluded.water_source, photo_id = coalesce(excluded.photo_id, fields.photo_id), updated_at = now()
       where fields.producer_id = excluded.producer_id`,
      [id, f.producer_id, f.name, geom ? JSON.stringify(geom) : null, JSON.stringify(f.contour), f.area_declared_ha ?? null, f.sown_on ?? null,
       f.irrigation, f.water_source, f.photo_id ?? null, user.id],
    );
    if (r.rowCount === 0) throw new ApiError(409, 'Ce champ appartient à un autre producteur.');
  });
  return json({ ok: true });
});
