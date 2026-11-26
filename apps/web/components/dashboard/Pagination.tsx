import Link from 'next/link';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';

/** Liens vers les pages voisines : 1 … 4 5 [6] 7 8 … 14 (la page courante et ses voisines, plus les extrémités). */
export function pageItems(page: number, pages: number): (number | '…')[] {
  const keep = new Set([1, pages, page - 2, page - 1, page, page + 1, page + 2].filter((n) => n >= 1 && n <= pages));
  const sorted = [...keep].sort((a, b) => a - b);
  const out: (number | '…')[] = [];
  sorted.forEach((n, i) => {
    if (i > 0 && n - sorted[i - 1] > 1) out.push('…');
    out.push(n);
  });
  return out;
}

/** « 51–100 sur 665 producteurs » */
export function rangeLabel(page: number, size: number, total: number, noun: [string, string]) {
  const label = total > 1 ? noun[1] : noun[0];
  if (total === 0) return `0 ${noun[0]}`;
  const from = (page - 1) * size + 1;
  const to = Math.min(page * size, total);
  return `${from}–${to} sur ${total} ${label}`;
}

type Search = Record<string, string | string[] | undefined>;

/** Navigation entre les pages d'une liste du tableau de bord ; garde les filtres de l'URL. */
export function Pagination({ path, search, page, pages }: { path: string; search: Search; page: number; pages: number }) {
  if (pages <= 1) return null;
  const href = (n: number) => {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(search)) if (k !== 'page' && typeof v === 'string' && v) qs.set(k, v);
    if (n > 1) qs.set('page', String(n));
    const s = qs.toString();
    return s ? `${path}?${s}` : path;
  };
  const link = 'inline-flex h-9 min-w-9 items-center justify-center rounded-md border border-line bg-white px-3 text-[14px] hover:bg-chalk';
  const off = 'inline-flex h-9 min-w-9 items-center justify-center rounded-md px-3 text-[14px] text-board-help';
  return (
    <nav aria-label="Pages" className="flex flex-wrap items-center justify-center gap-1.5 px-6 py-5">
      {page > 1 ? (
        <Link href={href(page - 1)} className={link} rel="prev">
          <ChevronLeft className="h-4 w-4" /> Précédent
        </Link>
      ) : (
        <span className={off} aria-disabled="true">
          <ChevronLeft className="h-4 w-4" /> Précédent
        </span>
      )}
      {pageItems(page, pages).map((n, i) =>
        n === '…' ? (
          <span key={`e${i}`} className={off}>
            …
          </span>
        ) : (
          <Link
            key={n}
            href={href(n)}
            aria-current={n === page ? 'page' : undefined}
            className={cn(link, n === page && 'border-forest bg-forest font-semibold text-white hover:bg-forest')}
          >
            {n}
          </Link>
        ),
      )}
      {page < pages ? (
        <Link href={href(page + 1)} className={link} rel="next">
          Suivant <ChevronRight className="h-4 w-4" />
        </Link>
      ) : (
        <span className={off} aria-disabled="true">
          Suivant <ChevronRight className="h-4 w-4" />
        </span>
      )}
    </nav>
  );
}
