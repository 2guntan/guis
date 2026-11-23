/** Message lisible d'une erreur Postgres / Supabase : « submit_file: dossier incomplet — … » → « Dossier incomplet — … ». */
export function humanError(err: unknown): string {
  let msg = '';
  if (typeof err === 'string') msg = err;
  else if (err && typeof err === 'object' && 'message' in err) msg = String((err as { message: unknown }).message ?? '');
  if (!msg) return 'Une erreur inattendue est survenue. Réessayez.';
  if (/Failed to fetch|NetworkError|fetch failed|Load failed/i.test(msg)) return 'Pas de connexion au serveur. Vos saisies sont gardées sur l’appareil ; nouvel essai automatique.';
  if (/JWT expired|invalid JWT|refresh_token/i.test(msg)) return 'Votre session a expiré. Reconnectez-vous.';
  if (/permission denied/i.test(msg)) return 'Action non autorisée pour votre compte.';
  if (/Invalid login credentials/i.test(msg)) return 'Adresse e-mail ou mot de passe incorrect.';
  if (/row-level security/i.test(msg)) return 'Dépôt refusé : ce dossier n’est plus modifiable par vous.';
  msg = msg.replace(/^[a-z_]+:\s*/, '');
  return msg.charAt(0).toUpperCase() + msg.slice(1);
}
