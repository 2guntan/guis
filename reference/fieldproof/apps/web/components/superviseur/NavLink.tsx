'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

export function NavLink({ href, children, exact }: { href: string; children: React.ReactNode; exact?: boolean }) {
  const path = usePathname();
  const active = exact ? path === href : path === href || path.startsWith(href + '/');
  return (
    <Link href={href} className={cn('shrink-0 rounded-lg px-3 py-1.5 text-sm transition', active ? 'bg-forest-800 text-paper' : 'text-forest-100/80 hover:bg-forest-800/60 hover:text-paper')}>
      {children}
    </Link>
  );
}
