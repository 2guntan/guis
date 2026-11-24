/**
 * Redirection relative (en-tête `Location: /chemin`) : derrière Caddy, l'URL de la requête vue par Next peut porter
 * l'adresse interne du conteneur ; un chemin relatif garde le domaine public du navigateur.
 */
export function redirectTo(path: string, status = 303) {
  return new Response(null, { status, headers: { Location: path } });
}

/** Chemin interne sûr pour « suite » : commence par un seul « / », sans barre oblique inverse ni caractère de contrôle. */
export function safeNext(v: string | null | undefined): string {
  const s = v ?? '';
  return /^\/(?![/\\])[^\\\u0000-\u001f]*$/.test(s) ? s : '/';
}
