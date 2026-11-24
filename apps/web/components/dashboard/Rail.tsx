'use client';

// Rail de navigation de la direction B (docs/design/SPECS.md) : 72 px, vert forêt, item actif #2E6A51.
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Map, Pentagon, User } from 'lucide-react';
import { LogoMark } from '@/components/Logo';
import { cn } from '@/lib/utils';

const ITEMS = [
  { href: '/', label: 'Carte', icon: Map, active: (p: string) => p === '/' },
  { href: '/champs', label: 'Champs', icon: Pentagon, active: (p: string) => p.startsWith('/champs') },
  { href: '/producteurs', label: 'Producteurs', icon: User, active: (p: string) => p.startsWith('/producteurs') },
];

export function Rail({ name, initials }: { name: string; initials: string }) {
  const path = usePathname();
  return (
    <nav aria-label="Navigation principale" className="fixed inset-y-0 left-0 z-[600] flex w-[72px] flex-col items-center bg-forest py-4">
      <Link href="/" aria-label="Guis, carte" className="mb-6">
        <LogoMark tone="cream" className="h-10 w-10" />
      </Link>
      <ul className="flex flex-col gap-2">
        {ITEMS.map(({ href, label, icon: Icon, active }) => {
          const on = active(path);
          return (
            <li key={href}>
              <Link
                href={href}
                aria-current={on ? 'page' : undefined}
                className={cn(
                  'flex w-[60px] flex-col items-center gap-1 rounded-[10px] py-2 text-[11px] leading-[14px]',
                  on ? 'bg-forest-rail font-semibold text-white' : 'font-medium text-forest-soft hover:bg-forest-rail/60 hover:text-white',
                )}
              >
                <Icon className="h-5 w-5" strokeWidth={1.8} />
                {label}
              </Link>
            </li>
          );
        })}
      </ul>
      <details className="group relative mt-auto">
        <summary
          title={name}
          className="flex h-10 w-10 cursor-pointer list-none items-center justify-center rounded-full bg-forest-rail text-[13px] font-semibold text-white [&::-webkit-details-marker]:hidden"
        >
          {initials}
        </summary>
        <div className="absolute bottom-0 left-12 w-56 rounded-md border border-line bg-white p-3 text-board-text shadow-lg">
          <div className="text-[14px] font-semibold">{name}</div>
          <div className="text-[13px] text-board-help">Administrateur</div>
          <form action="/deconnexion" method="post" className="mt-3">
            <button className="btn-b-ghost w-full">Se déconnecter</button>
          </form>
        </div>
      </details>
    </nav>
  );
}
