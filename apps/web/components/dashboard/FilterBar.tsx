'use client';

// Repris de Fieldproof (components/superviseur/FilterBar.tsx) : filtres gardés dans l'URL. Direction B :
// champs de 40 px, case « À vérifier seulement (N) », filtres des champs ou des producteurs.
import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { ChevronDown, Search } from 'lucide-react';

type Select = { key: string; label: string; options: { value: string; label: string }[] };

export function FilterBar({
  path,
  placeholder,
  selects,
  check,
  checks = [],
  count,
}: {
  path: string;
  placeholder: string;
  selects: Select[];
  check?: { key: string; label: string };
  checks?: { key: string; label: string }[];
  count: string;
}) {
  const router = useRouter();
  const sp = useSearchParams();
  const [q, setQ] = useState(sp.get('q') ?? '');

  function push(key: string, value: string) {
    const next = new URLSearchParams(sp.toString());
    if (value) next.set(key, value);
    else next.delete(key);
    router.replace(`${path}?${next.toString()}`);
  }
  useEffect(() => {
    const t = setTimeout(() => {
      if ((sp.get('q') ?? '') !== q) push('q', q.trim());
    }, 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  return (
    <div className="flex flex-wrap items-center gap-2.5 px-6 py-3.5">
      <label className="relative">
        <span className="sr-only">Rechercher</span>
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-board-help" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={placeholder} className="input-b w-[240px] pl-9" />
      </label>
      {selects.map((s) => (
        <label key={s.key} className="relative">
          <span className="sr-only">{s.label}</span>
          <select aria-label={s.label} className="input-b appearance-none pr-9" value={sp.get(s.key) ?? ''} onChange={(e) => push(s.key, e.target.value)}>
            <option value="">{s.label}</option>
            {s.options.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          <ChevronDown className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-board-text" />
        </label>
      ))}
      {[...(check ? [check] : []), ...checks].map((c) => (
        <label key={c.key} className="input-b flex cursor-pointer items-center gap-2.5">
          <input type="checkbox" className="h-4 w-4 accent-forest" checked={sp.get(c.key) === '1'} onChange={(e) => push(c.key, e.target.checked ? '1' : '')} />
          {c.label}
        </label>
      ))}
      <span className="ml-auto text-[14px] text-board-muted">{count}</span>
    </div>
  );
}
