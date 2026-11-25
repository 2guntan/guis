import { z } from 'zod';
import { BLOCKED_MESSAGE, attemptLogin, createSession } from '@/lib/auth';
import { body, errorResponse, json } from '@/lib/api';
import { can } from '@/lib/rights';

const Login = z.object({ phone: z.string().min(6), password: z.string().min(1) });

/** Connexion de l'app Android : renvoie un jeton à envoyer en `Authorization: Bearer`. */
export async function POST(req: Request) {
  try {
    const { phone, password } = await body(req, Login);
    const r = await attemptLogin(phone, password);
    if (r && 'blocked' in r) return json({ error: BLOCKED_MESSAGE, code: 'blocked' }, 429);
    if (!r) return json({ error: 'Numéro ou mot de passe incorrect.' }, 401);
    const user = r.user;
    if (!can(user, 'use_app')) return json({ error: 'Ce compte s’utilise sur le tableau de bord.', code: 'dashboard_only' }, 403);
    return json({ token: await createSession(user.id), user });
  } catch (e) {
    return errorResponse(e);
  }
}
