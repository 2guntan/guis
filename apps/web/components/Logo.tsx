import { cn } from '@/lib/utils';

/**
 * Logo Guis (docs/design/fondations.png) : carré arrondi, soleil ocre sur l'horizon, sillons.
 * `tone="forest"` : carré vert forêt, traits crème (app, panneau de connexion) ;
 * `tone="cream"` : carré crème, traits vert forêt (rail du tableau de bord).
 */
export function LogoMark({ tone = 'forest', className }: { tone?: 'forest' | 'cream'; className?: string }) {
  const bg = tone === 'forest' ? '#1F4D3A' : '#F4EEE1';
  const fg = tone === 'forest' ? '#F4EEE1' : '#1F4D3A';
  return (
    <svg viewBox="0 0 64 64" className={cn('h-10 w-10', className)} aria-hidden>
      <rect width="64" height="64" rx="14" fill={bg} />
      <path d="M11 34 C17 23 25 19 32 19 C39 19 47 23 53 34 Z" fill="none" stroke={fg} strokeWidth="4.2" strokeLinejoin="round" />
      <circle cx="32" cy="22.5" r="6.5" fill="#C8892B" />
      <path d="M17 42 H47 M24 49.5 H40" stroke={fg} strokeWidth="4.2" strokeLinecap="round" />
    </svg>
  );
}

export function Logo({ tone = 'forest', light, className }: { tone?: 'forest' | 'cream'; light?: boolean; className?: string }) {
  return (
    <span className={cn('inline-flex items-center gap-3', className)}>
      <LogoMark tone={tone} className="h-11 w-11" />
      <span className={cn('font-display text-[28px] font-semibold', light ? 'text-sand' : 'text-forest')}>Guis</span>
    </span>
  );
}
