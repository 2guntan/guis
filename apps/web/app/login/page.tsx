import type { Metadata } from 'next';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { Logo } from '@/components/Logo';
import { SESSION_COOKIE, userFromToken } from '@/lib/auth';

export const metadata: Metadata = { title: 'Connexion' };

// Mise en page reprise de Fieldproof (app/login/page.tsx) : formulaire HTML simple, sans Supabase.
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ erreur?: string; suite?: string }> }) {
  const sp = await searchParams;
  const user = await userFromToken((await cookies()).get(SESSION_COOKIE)?.value);
  if (user?.role === 'admin') redirect('/');
  const message =
    sp.erreur === 'identifiants'
      ? 'Numéro ou mot de passe incorrect.'
      : sp.erreur === 'role' || user
        ? 'Ce compte est un compte agent : il sert dans l’app Android. Le tableau de bord est réservé aux administrateurs.'
        : null;
  return (
    <main className="grid min-h-dvh lg:grid-cols-[1.05fr_1fr]">
      <section className="topo relative hidden overflow-hidden bg-forest-900 text-paper lg:flex lg:flex-col lg:justify-between lg:p-14">
        <Logo light />
        <div className="max-w-md">
          <h1 className="font-display text-[44px] leading-[1.05] text-paper">Les champs relevés sur le terrain, suivis depuis le ciel.</h1>
          <p className="mt-5 text-[15px] leading-relaxed text-forest-100/80">
            Les agents relèvent les producteurs, leurs semences et le contour de leurs champs. Le satellite suit chaque champ depuis son semis.
          </p>
        </div>
        <p className="text-xs text-forest-100/50">Guis — coopérative et IBRIZ</p>
      </section>
      <section className="flex flex-col">
        <div className="flex items-center gap-2 bg-forest-900 px-5 py-4 lg:hidden">
          <Logo light />
        </div>
        <div className="flex flex-1 items-center justify-center px-5 py-10 sm:px-10">
          <div className="w-full max-w-sm">
            <h2 className="text-3xl">Connexion</h2>
            <p className="mt-2 text-sm text-ink-soft">Avec le numéro de téléphone et le mot de passe de votre compte.</p>
            {message && (
              <p role="alert" className="mt-5 rounded-lg border border-clay-500/40 bg-clay-50 px-3 py-2.5 text-sm text-clay-700">
                {message}
              </p>
            )}
            <form action="/connexion" method="post" className="mt-8 space-y-5">
              <input type="hidden" name="suite" value={sp.suite ?? ''} />
              <div>
                <label htmlFor="phone" className="field-label">Numéro de téléphone</label>
                <input id="phone" name="phone" type="tel" autoComplete="username" required className="field-input" placeholder="77 123 45 67" />
              </div>
              <div>
                <label htmlFor="password" className="field-label">Mot de passe</label>
                <input id="password" name="password" type="password" autoComplete="current-password" required className="field-input" />
              </div>
              <button type="submit" className="inline-flex h-14 w-full items-center justify-center rounded-xl bg-forest-800 px-6 text-base font-medium text-paper hover:bg-forest-900">
                Se connecter
              </button>
            </form>
          </div>
        </div>
      </section>
    </main>
  );
}
