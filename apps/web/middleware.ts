import { NextResponse, type NextRequest } from 'next/server';

// Repris de Fieldproof (middleware.ts), sans Supabase : sans cookie de session, les pages du tableau de bord
// renvoient vers /login. La validité de la session et le rôle sont vérifiés côté serveur (lib/auth.ts).
export function middleware(request: NextRequest) {
  if (request.cookies.get('guis_session')) return NextResponse.next();
  const url = request.nextUrl.clone();
  url.pathname = '/login';
  url.search = '';
  if (request.nextUrl.pathname !== '/') url.searchParams.set('suite', request.nextUrl.pathname + request.nextUrl.search);
  return NextResponse.redirect(url);
}

export const config = {
  // L'API (jeton de l'app), la connexion et les fichiers statiques ne passent pas par ici.
  matcher: ['/((?!api/|login|connexion|deconnexion|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|webp)$).*)'],
};
