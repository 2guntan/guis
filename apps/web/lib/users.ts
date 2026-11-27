import 'server-only';
import bcrypt from 'bcryptjs';
import type { PoolClient } from 'pg';
import { ApiError } from '@/lib/api';
import type { User } from '@/lib/auth';
import { query, tx } from '@/lib/db';
import { normalizePhone } from '@/lib/phone';
import type { Role } from '@/lib/rights';
import { generateSecret } from '@/lib/secrets';

/**
 * Comptes (spec 2guntan/guis#24) : création, modification et réinitialisation par l'admin ;
 * réinitialisation du code d'un agent par le coordinateur (page « Attribution »).
 * Un secret généré n'est renvoyé qu'une fois, à l'appelant ; seule son empreinte est gardée.
 */
export type Account = {
  id: string;
  name: string;
  phone: string;
  role: Role;
  active: boolean;
  last_sync_at: string | null;
  created_at: string;
  last_reset_at: string | null;
  last_reset_by: string | null;
  communes: string[];
  deletable: boolean;
};

export type EventAction = 'create' | 'update' | 'role' | 'reset' | 'deactivate' | 'reactivate' | 'delete';

/** Téléphone de connexion : numéro sénégalais mobile, normalisé avec l'indicatif 221. */
export function loginPhone(raw: string): string {
  const phone = normalizePhone(raw);
  if (!/^221[37]\d{8}$/.test(phone)) throw new ApiError(422, `Téléphone « ${raw} » invalide : 9 chiffres attendus (ex. 77 123 45 67).`);
  return phone;
}

export async function logEvent(c: PoolClient, actor: User, targetId: string | null, action: EventAction, detail?: string) {
  await c.query('insert into account_events (actor_id, target_id, action, detail) values ($1, $2, $3, $4)', [actor.id, targetId, action, detail ?? null]);
}

/** Un compte est supprimable seulement si aucun enregistrement ne le référence. */
const DELETABLE = `not exists (select 1 from producers x where x.created_by = u.id or x.consent_by = u.id)
  and not exists (select 1 from fields x where x.created_by = u.id)
  and not exists (select 1 from photos x where x.uploaded_by = u.id)
  and not exists (select 1 from producer_distinct x where x.decided_by = u.id)
  and not exists (select 1 from producer_merges x where x.merged_by = u.id)`;

export async function listAccounts(): Promise<Account[]> {
  return query<Account>(
    `select u.id, u.name, u.phone, u.role, u.active, u.last_sync_at, u.created_at,
            r.at as last_reset_at, a.name as last_reset_by,
            coalesce((select array_agg(ac.commune order by ac.commune) from agent_communes ac where ac.user_id = u.id), '{}') as communes,
            ${DELETABLE} as deletable
       from users u
       left join lateral (select e.at, e.actor_id from account_events e where e.target_id = u.id and e.action = 'reset' order by e.at desc limit 1) r on true
       left join users a on a.id = r.actor_id
      order by u.active desc, case u.role when 'admin' then 0 when 'coordinator' then 1 else 2 end, u.name`,
  );
}

export async function listEvents(limit = 30) {
  return query<{ at: string; action: EventAction; detail: string | null; actor: string | null; target: string | null }>(
    `select e.at, e.action, e.detail, a.name as actor, t.name as target
       from account_events e left join users a on a.id = e.actor_id left join users t on t.id = e.target_id
      order by e.at desc limit $1`,
    [limit],
  );
}

function duplicatePhone(e: unknown): never {
  const pg = e as { code?: string; constraint?: string };
  if (pg?.code === '23505') throw new ApiError(409, 'Ce téléphone est déjà utilisé par un autre compte.');
  throw e;
}

async function setSecret(c: PoolClient, id: string, role: Role, phone: string) {
  const secret = generateSecret(role, phone);
  await c.query('update users set password_hash = $2 where id = $1', [id, await bcrypt.hash(secret, 10)]);
  await c.query('delete from sessions where user_id = $1', [id]);
  await c.query('delete from login_attempts where phone = $1', [phone]);
  return secret;
}

export async function createAccount(actor: User, input: { name: string; phone: string; role: Role }) {
  const phone = loginPhone(input.phone);
  const name = input.name.trim();
  if (!name) throw new ApiError(422, 'Le nom est obligatoire.');
  return tx(async (c) => {
    const secret = generateSecret(input.role, phone);
    const r = await c
      .query<{ id: string }>('insert into users (phone, name, role, password_hash) values ($1, $2, $3, $4) returning id', [
        phone,
        name,
        input.role,
        await bcrypt.hash(secret, 10),
      ])
      .catch(duplicatePhone);
    const id = r.rows[0].id;
    await c.query('delete from login_attempts where phone = $1', [phone]);
    await logEvent(c, actor, id, 'create', input.role);
    return { id, name, phone, role: input.role, secret };
  });
}

export async function updateAccount(actor: User, id: string, input: { name?: string; phone?: string; role?: Role }) {
  return tx(async (c) => {
    const cur = (await c.query<{ name: string; phone: string; role: Role }>('select name, phone, role from users where id = $1 for update', [id])).rows[0];
    if (!cur) throw new ApiError(404, 'Compte introuvable.');
    const name = input.name === undefined ? cur.name : input.name.trim();
    if (!name) throw new ApiError(422, 'Le nom est obligatoire.');
    const phone = input.phone === undefined ? cur.phone : loginPhone(input.phone);
    const role = input.role ?? cur.role;
    if (id === actor.id && role !== cur.role) throw new ApiError(409, 'Vous ne pouvez pas changer votre propre profil.');
    await c.query('update users set name = $2, phone = $3, role = $4 where id = $1', [id, name, phone, role]).catch(duplicatePhone);
    if (role !== cur.role) {
      if (cur.role === 'agent') await c.query('delete from agent_communes where user_id = $1', [id]);
      await logEvent(c, actor, id, 'role', `${cur.role} → ${role}`);
    }
    if (name !== cur.name || phone !== cur.phone) await logEvent(c, actor, id, 'update');
    return { id, name, phone, role };
  });
}

/** Nouveau secret selon le profil, sessions fermées, blocage levé. `onlyAgents` : réinitialisation par le coordinateur. */
export async function resetSecret(actor: User, id: string, { onlyAgents = false } = {}) {
  return tx(async (c) => {
    const u = (await c.query<{ name: string; phone: string; role: Role }>('select name, phone, role from users where id = $1 for update', [id])).rows[0];
    if (!u) throw new ApiError(404, 'Compte introuvable.');
    if (onlyAgents && u.role !== 'agent') throw new ApiError(403, 'Seul le code d’un agent peut être réinitialisé ici.');
    const secret = await setSecret(c, id, u.role, u.phone);
    await logEvent(c, actor, id, 'reset');
    return { id, name: u.name, phone: u.phone, role: u.role, secret };
  });
}

async function assertNotLastAdmin(c: PoolClient, id: string) {
  const r = await c.query<{ n: number }>(`select count(*)::int as n from users where role = 'admin' and active and id <> $1`, [id]);
  if (r.rows[0].n === 0) throw new ApiError(409, 'Il doit rester au moins un admin actif.');
}

/** Désactiver : plus de connexion, sessions fermées, attributions retirées ; l'historique reste. */
export async function deactivateAccount(actor: User, id: string) {
  if (id === actor.id) throw new ApiError(409, 'Vous ne pouvez pas désactiver votre propre compte.');
  return tx(async (c) => {
    const u = (await c.query<{ role: Role; active: boolean }>('select role, active from users where id = $1 for update', [id])).rows[0];
    if (!u) throw new ApiError(404, 'Compte introuvable.');
    if (u.role === 'admin') await assertNotLastAdmin(c, id);
    await c.query('update users set active = false where id = $1', [id]);
    await c.query('delete from sessions where user_id = $1', [id]);
    await c.query('delete from agent_communes where user_id = $1', [id]);
    if (u.active) await logEvent(c, actor, id, 'deactivate');
    return { id, active: false };
  });
}

/** Réactiver : la connexion redevient possible avec le secret actuel ; les attributions ne reviennent pas seules. */
export async function reactivateAccount(actor: User, id: string) {
  return tx(async (c) => {
    const u = (await c.query<{ active: boolean }>('select active from users where id = $1 for update', [id])).rows[0];
    if (!u) throw new ApiError(404, 'Compte introuvable.');
    await c.query('update users set active = true where id = $1', [id]);
    if (!u.active) await logEvent(c, actor, id, 'reactivate');
    return { id, active: true };
  });
}

/** Supprimer : seulement un compte qui n'a jamais rien fait. */
export async function deleteAccount(actor: User, id: string) {
  if (id === actor.id) throw new ApiError(409, 'Vous ne pouvez pas supprimer votre propre compte.');
  return tx(async (c) => {
    const u = (await c.query<{ role: Role; name: string; deletable: boolean }>(
      `select u.role, u.name, ${DELETABLE} as deletable from users u where u.id = $1 for update`,
      [id],
    )).rows[0];
    if (!u) throw new ApiError(404, 'Compte introuvable.');
    if (!u.deletable) throw new ApiError(409, 'Ce compte a déjà travaillé : désactivez-le.');
    if (u.role === 'admin') await assertNotLastAdmin(c, id);
    await logEvent(c, actor, id, 'delete', u.name);
    await c.query('delete from users where id = $1', [id]);
    return { id, deleted: true };
  });
}
