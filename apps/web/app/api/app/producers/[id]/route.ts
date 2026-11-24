import { z } from 'zod';
import { ApiError, body, handle, json, uuid } from '@/lib/api';
import { tx } from '@/lib/db';
import { normalizePhone } from '@/lib/phone';
import { assertCanEdit } from '@/lib/scope';

const opt = z.string().trim().max(200).nullish().transform((v) => (v ? v : null));
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullish();

const Producer = z.object({
  last_name: z.string().trim().min(1).max(100),
  first_name: z.string().trim().min(1).max(100),
  phone: opt,
  member_card: opt,
  sex: z.enum(['F', 'H']).nullish(),
  village: opt,
  photo_id: uuid.nullish(),
  consent_at: z.string().datetime({ offset: true }),
  seeds: z
    .array(z.object({ id: uuid, variety: z.string().trim().min(1).max(100), quantity_kg: z.number().positive().max(100000), received_on: day }))
    .max(50)
    .default([]),
  deleted_seed_ids: z.array(uuid).max(50).default([]),
});

/** Enregistre un producteur (création ou mise à jour, par identifiant) et ses semences reçues. */
export const PUT = handle<{ params: Promise<{ id: string }> }>(async (req, user, { params }) => {
  const id = uuid.parse((await params).id);
  const p = await body(req, Producer);
  if (!p.consent_at) throw new ApiError(422, 'Le consentement du producteur est obligatoire.');
  await tx(async (c) => {
    await assertCanEdit(c, user, id);
    // Un producteur créé par un agent qui n'a qu'une commune est rattaché à cette commune.
    await c.query(
      `insert into producers (id, last_name, first_name, phone, member_card, sex, village, photo_id, consent_at, consent_by, created_by, commune)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10,
               (select min(commune) from agent_communes where user_id = $10 having count(*) = 1))
       on conflict (id) do update set last_name = excluded.last_name, first_name = excluded.first_name, phone = excluded.phone,
         member_card = excluded.member_card, sex = excluded.sex, village = excluded.village,
         photo_id = coalesce(excluded.photo_id, producers.photo_id),
         consent_at = coalesce(producers.consent_at, excluded.consent_at),
         consent_by = coalesce(producers.consent_by, excluded.consent_by), updated_at = now()`,
      [id, p.last_name, p.first_name, p.phone ? normalizePhone(p.phone) : null, p.member_card, p.sex ?? null, p.village, p.photo_id ?? null, p.consent_at, user.id],
    );
    if (p.village) await c.query('insert into villages (name) values ($1) on conflict do nothing', [p.village]);
    for (const s of p.seeds) {
      const r = await c.query(
        `insert into seed_distributions (id, producer_id, variety, quantity_kg, received_on) values ($1, $2, $3, $4, $5)
         on conflict (id) do update set variety = excluded.variety, quantity_kg = excluded.quantity_kg, received_on = excluded.received_on, updated_at = now()
         where seed_distributions.producer_id = excluded.producer_id`,
        [s.id, id, s.variety, s.quantity_kg, s.received_on ?? null],
      );
      if (r.rowCount === 0) throw new ApiError(409, 'Cette semence appartient à un autre producteur.');
    }
    if (p.deleted_seed_ids.length) {
      await c.query('delete from seed_distributions where producer_id = $1 and id = any($2::uuid[])', [id, p.deleted_seed_ids]);
    }
  });
  return json({ ok: true });
});
