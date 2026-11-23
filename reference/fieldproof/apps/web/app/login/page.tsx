import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { Logo, LogoMark } from '@/components/Logo';
import { getSession, homeFor } from '@/lib/session';
import { LoginForm } from './LoginForm';

export const metadata: Metadata = { title: 'Connexion' };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ suite?: string; erreur?: string }> }) {
  const sp = await searchParams;
  const s = await getSession();
  if (s && homeFor(s.memberships) && !sp.erreur) redirect(homeFor(s.memberships)!);

  return (
    <main className="grid min-h-dvh lg:grid-cols-[1.05fr_1fr]">
      <section className="topo relative hidden overflow-hidden bg-forest-900 text-paper lg:flex lg:flex-col lg:justify-between lg:p-14">
        <Logo light />
        <div className="max-w-md">
          <ParcelIllustration />
          <h1 className="mt-10 font-display text-[44px] leading-[1.05] text-paper">
            Le dossier du client, collecté une fois, prouvé par le satellite.
          </h1>
          <p className="mt-5 text-[15px] leading-relaxed text-forest-100/80">
            Les agents terrain constituent le dossier client et tracent la parcelle. Le superviseur vérifie, puis envoie les paquets à la caisse par lien sécurisé.
          </p>
        </div>
        <p className="text-xs text-forest-100/50">Pilote IBRIZ × PAMECAS — Niayes et Ziguinchor</p>
      </section>

      <section className="flex flex-col">
        <div className="flex items-center gap-2 bg-forest-900 px-5 py-4 lg:hidden">
          <LogoMark />
          <span className="font-display text-xl text-paper">Fieldproof</span>
        </div>
        <div className="flex flex-1 items-center justify-center px-5 py-10 sm:px-10">
          <div className="w-full max-w-sm">
            <h2 className="text-3xl">Connexion</h2>
            <p className="mt-2 text-sm text-ink-soft">Avec l’adresse e-mail de votre compte agent ou superviseur.</p>
            {sp.erreur === 'role' && (
              <p className="mt-5 rounded-lg border border-ochre-400/50 bg-ochre-50 px-3 py-2.5 text-sm text-ochre-700">
                Ce compte n’a pas de rôle actif sur Fieldproof. Contactez votre administrateur.
              </p>
            )}
            <LoginForm next={sp.suite} />
          </div>
        </div>
      </section>
    </main>
  );
}

function ParcelIllustration() {
  return (
    <svg viewBox="0 0 320 200" className="w-full max-w-sm" aria-hidden>
      <defs>
        <pattern id="rows" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(-18)">
          <line x1="0" y1="0" x2="0" y2="8" stroke="#7FA68C" strokeOpacity="0.35" strokeWidth="3" />
        </pattern>
      </defs>
      <path d="M40 150 70 40 200 26 262 104 190 176z" fill="url(#rows)" />
      <path d="M40 150 70 40 200 26 262 104 190 176z" fill="none" stroke="#D9A23F" strokeWidth="2" strokeLinejoin="round" strokeDasharray="600" className="animate-draw" style={{ animationDuration: '2.4s' }} />
      {[[40, 150], [70, 40], [200, 26], [262, 104], [190, 176]].map(([x, y]) => (
        <circle key={`${x}-${y}`} cx={x} cy={y} r="4.5" fill="#FFFDF7" stroke="#C08A2B" strokeWidth="2" />
      ))}
      <g fontFamily="var(--font-sans)" fontSize="11" fill="#CFE0D4">
        <text x="210" y="190">1,18 ha</text>
        <text x="84" y="104" fill="#FFFDF7" fontSize="12">Parcelle nord</text>
      </g>
    </svg>
  );
}
