import { cn } from '@/lib/utils';

/** Logo Guis : un œil sur un champ (gis, « voir »). */
export function Logo({ light, className }: { light?: boolean; className?: string }) {
  return (
    <span className={cn('inline-flex items-center gap-2', className)}>
      <svg viewBox="0 0 32 32" className="h-8 w-8" aria-hidden>
        <rect width="32" height="32" rx="9" fill={light ? '#2F6B4F' : '#163A2C'} />
        <path d="M5 17c3-5 7-7.5 11-7.5S24 12 27 17c-3 4.5-7 7-11 7s-8-2.5-11-7z" fill="none" stroke="#D9A23F" strokeWidth="2" />
        <circle cx="16" cy="16.5" r="3.6" fill="#FFFDF7" />
      </svg>
      <span className={cn('font-display text-xl', light ? 'text-paper' : 'text-forest-900')}>Guis</span>
    </span>
  );
}
