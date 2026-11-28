import { userFromRequest } from '@/lib/auth';
import { query } from '@/lib/db';
import { redirectTo } from '@/lib/redirect';
import { can } from '@/lib/rights';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * « Marquer comme vues » sur la fiche champ : toutes les alertes encore ouvertes du champ
 * sortent du compteur « à vérifier ». Une alerte qui disparaît puis revient est de nouveau
 * à vérifier (db/migrations/0012_alertes_vues.sql).
 */
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const user = await userFromRequest(req);
  if (!user) return redirectTo('/login');
  if (!can(user, 'use_dashboard')) return redirectTo('/login?refus=1');
  if (!can(user, 'review_alerts')) return new Response('Votre compte ne peut pas marquer les alertes comme vues.', { status: 403 });
  const id = (await params).id;
  if (!UUID.test(id)) return new Response('Champ inconnu.', { status: 404 });
  await query(
    `insert into alert_reviews (field_id, code, reviewed_by)
     select s.field_id, a->>'code', $2 from field_status s, jsonb_array_elements(open_alerts(s.field_id, s.alerts)) a
      where s.field_id = $1
     on conflict do nothing`,
    [id, user.id],
  );
  return redirectTo(`/champs/${id}?vu=1#alertes`);
}
