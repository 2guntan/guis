import type { Metadata } from 'next';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { AlertTriangle, Info } from 'lucide-react';
import { LogoMark } from '@/components/Logo';
import { SESSION_COOKIE, userFromToken } from '@/lib/auth';
import { campaignLabel } from '@/lib/design';
import { PasswordField } from './PasswordField';

export const metadata: Metadata = { title: 'Connexion' };

// W1 « Connexion », direction A (docs/design/web/w1-connexion.png). Mise en page reprise de Fieldproof
// (app/login/page.tsx) : panneau vert à gauche, formulaire HTML simple à droite, sans Supabase.
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ erreur?: string; suite?: string }> }) {
  const sp = await searchParams;
  const user = await userFromToken((await cookies()).get(SESSION_COOKIE)?.value);
  if (user?.role === 'admin') redirect('/');
  const wrong = sp.erreur === 'identifiants';
  const agent = sp.erreur === 'role' || (!!user && !wrong);
  return (
    <main className="grid min-h-dvh bg-sand text-ink lg:grid-cols-[600fr_680fr]">
      <section className="relative hidden overflow-hidden bg-[#1F3A2D] text-sand lg:flex lg:flex-col lg:justify-between lg:p-16">
        <div className="flex items-center gap-3">
          <LogoMark tone="cream" className="h-11 w-11" />
          <span className="font-display text-[28px] font-semibold text-sand">Guis</span>
        </div>
        <Sun />
        <div className="relative max-w-md">
          <h1 className="text-[44px] leading-[1.18] text-sand">Les champs relevés sur le terrain, suivis depuis le ciel.</h1>
          <p className="mt-5 text-[15px] text-sand/75">{campaignLabel().replace('-', '–')} · Niayes</p>
        </div>
      </section>
      <section className="flex items-center justify-center px-6 py-12">
        <div className="w-full max-w-[380px]">
          <div className="mb-8 flex items-center gap-3 lg:hidden">
            <LogoMark className="h-11 w-11" />
            <span className="font-display text-[28px] font-semibold text-forest">Guis</span>
          </div>
          <h2 className="text-[36px] leading-[1.1] text-ink">Connexion</h2>
          <p className="mt-2 text-[15px] text-ink-muted">Tableau de bord de la coopérative et d’IBRIZ.</p>
          <form action="/connexion" method="post" className="mt-6 space-y-4">
            <input type="hidden" name="suite" value={sp.suite ?? ''} />
            <div>
              <label htmlFor="phone" className="mb-2 block text-[14px] font-medium">
                Numéro de téléphone
              </label>
              <input
                id="phone"
                name="phone"
                type="tel"
                autoComplete="username"
                required
                placeholder="77 123 45 67"
                className="h-12 w-full rounded-md border border-sand-deep bg-white px-4 text-[15px] text-ink placeholder:text-ink-muted/60 focus:border-forest focus:outline-none"
              />
            </div>
            <div>
              <label htmlFor="password" className="mb-2 block text-[14px] font-medium">
                Mot de passe
              </label>
              <PasswordField />
            </div>
            <button type="submit" className="!mt-6 inline-flex h-12 w-full items-center justify-center rounded-md bg-forest text-[15px] font-semibold text-white hover:bg-forest-dark">
              Se connecter
            </button>
          </form>
          {wrong && (
            <p role="alert" className="mt-6 flex items-start gap-3 rounded-md bg-clay-soft px-4 py-3 text-[14px] text-clay-text">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-clay" /> Numéro ou mot de passe incorrect.
            </p>
          )}
          {agent && (
            <p role="alert" className="mt-6 flex items-start gap-3 rounded-md bg-sky-soft px-4 py-3 text-[14px] text-sky-text">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-sky" /> Ce compte est un compte agent : il se connecte depuis l’app Android, pas depuis le tableau de bord.
            </p>
          )}
        </div>
      </section>
    </main>
  );
}

/** Soleil ocre posé sur l'horizon, rayons fins vers le bas (panneau de gauche). */
function Sun() {
  return (
    <svg className="pointer-events-none absolute inset-x-0 top-[40%] h-[60%] w-full" viewBox="0 0 600 480" preserveAspectRatio="xMidYMin slice" aria-hidden>
      <line x1="0" y1="64" x2="600" y2="64" stroke="#F4EEE1" strokeOpacity="0.18" />
      {Array.from({ length: 13 }, (_, i) => {
        const a = Math.PI * (0.08 + (i * 0.84) / 12);
        return <line key={i} x1="300" y1="64" x2={300 + Math.cos(a) * 640} y2={64 + Math.sin(a) * 640} stroke="#F4EEE1" strokeOpacity="0.09" />;
      })}
      <circle cx="300" cy="64" r="64" fill="#C8892B" fillOpacity="0.9" />
      <rect x="236" y="64" width="128" height="64" fill="#1F3A2D" fillOpacity="0.55" />
    </svg>
  );
}
