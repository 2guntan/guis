import 'server-only';
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { userFromRequest, type User } from '@/lib/auth';
import { can, type Action } from '@/lib/rights';
import { validationMessage } from '@/lib/validation-fr';

// Messages de validation en français : ils s'affichent tels quels dans l'app de l'agent.
z.config(z.locales.fr());

/**
 * Réponses de l'API de l'app Android. Contrat avec l'outbox de l'app :
 * - 2xx : accepté ;
 * - 400, 404, 409, 422 : refus définitif (message en français dans `error`) ;
 * - 401, 408, 429, 5xx : on réessaiera plus tard.
 */
export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export const json = (data: unknown, status = 200) => NextResponse.json(data, { status });

export function handle<C>(fn: (req: Request, user: User, ctx: C) => Promise<Response>, opts: { can?: Action } = {}) {
  return async (req: Request, ctx: C) => {
    try {
      const user = await userFromRequest(req);
      if (!user) throw new ApiError(401, 'Session expirée : reconnectez-vous.');
      if (opts.can && !can(user, opts.can)) throw new ApiError(403, 'Votre compte n’a pas accès à cette action.');
      return await fn(req, user, ctx);
    } catch (e) {
      return errorResponse(e);
    }
  };
}

export function errorResponse(e: unknown) {
  if (e instanceof ApiError) return json({ error: e.message }, e.status);
  if (e instanceof z.ZodError) {
    return json({ error: validationMessage(e) }, 422);
  }
  const pg = e as { code?: string; constraint?: string; message?: string };
  if (pg?.code === '23514' && pg.constraint === 'fields_geom_valid') return json({ error: 'Le contour du champ est invalide (il se croise).' }, 422);
  if (pg?.code === '23505' && pg.constraint === 'producers_card_uq') return json({ error: 'Ce numéro de carte de membre est déjà utilisé par un autre producteur.' }, 409);
  if (pg?.code === '23503') return json({ error: 'Le producteur de ce champ est inconnu du serveur.' }, 409);
  if (pg?.code && /^(22|23)/.test(pg.code)) {
    // Le message de PostgreSQL (en anglais, technique) reste dans le journal du serveur.
    console.error('Donnée refusée par la base', pg.code, pg.constraint, pg.message);
    return json({ error: 'Une valeur de la fiche n’est pas acceptée par le serveur. Vérifiez la fiche, puis enregistrez à nouveau.' }, 422);
  }
  console.error(e);
  return json({ error: 'Erreur du serveur, réessai plus tard.' }, 500);
}

export async function body<T>(req: Request, schema: z.ZodType<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    throw new ApiError(400, 'Corps JSON illisible.');
  }
  return schema.parse(raw);
}

export const uuid = z.string().uuid();
