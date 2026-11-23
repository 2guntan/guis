import Link from 'next/link';
import { LogOut } from 'lucide-react';
import { Logo } from '@/components/Logo';
import { cleanName } from '@/lib/format';

export function AppHeader({ home, name, role, nav }: { home: string; name?: string | null; role: string; nav?: React.ReactNode }) {
  return (
    <header className="sticky top-0 z-[500] border-b border-forest-800 bg-forest-900 text-paper">
      <div className="mx-auto flex h-14 max-w-7xl items-center gap-4 px-4 sm:px-6">
        <Link href={home} className="shrink-0"><Logo light /></Link>
        <nav className="hidden flex-1 items-center gap-1 md:flex">{nav}</nav>
        <div className="ml-auto flex items-center gap-3">
          <div className="hidden text-right leading-tight sm:block">
            <div className="text-sm font-medium">{cleanName(name)}</div>
            <div className="text-[11px] text-forest-100/70">{role}</div>
          </div>
          <form action="/deconnexion" method="post">
            <button className="inline-flex h-9 items-center gap-1.5 rounded-lg px-2.5 text-sm text-forest-100 hover:bg-forest-800" title="Se déconnecter">
              <LogOut className="h-4 w-4" />
              <span className="hidden sm:inline">Quitter</span>
            </button>
          </form>
        </div>
      </div>
      {nav && <nav className="flex gap-1 overflow-x-auto border-t border-forest-800 px-3 py-1.5 md:hidden">{nav}</nav>}
    </header>
  );
}
