'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Search } from 'lucide-react';
import { FILE_STATUS } from '@/lib/labels';

export function FilterBar({ agents, regions }: { agents: { id: string; name: string }[]; regions: { id: string; name: string }[] }) {
  const router = useRouter();
  const sp = useSearchParams();
  const [q, setQ] = useState(sp.get('q') ?? '');

  function push(key: string, value: string) {
    const next = new URLSearchParams(sp.toString());
    if (value) next.set(key, value); else next.delete(key);
    router.replace(`/superviseur/dossiers?${next.toString()}`);
  }
  useEffect(() => {
    const t = setTimeout(() => { if ((sp.get('q') ?? '') !== q) push('q', q.trim()); }, 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const sel = 'h-11 rounded-xl border border-sand-300 bg-surface px-3 text-sm text-ink focus:border-forest-500 focus:outline-none';
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[1.6fr_1fr_1fr_1fr]">
      <label className="relative">
        <span className="sr-only">Rechercher</span>
        <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-faint" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nom du client ou référence FP-…" className="h-11 w-full rounded-xl border border-sand-300 bg-surface pl-10 pr-3 text-sm focus:border-forest-500 focus:outline-none" />
      </label>
      <select aria-label="Statut" className={sel} value={sp.get('statut') ?? ''} onChange={(e) => push('statut', e.target.value)}>
        <option value="">Tous les statuts</option>
        {Object.entries(FILE_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
      </select>
      <select aria-label="Agent terrain" className={sel} value={sp.get('agent') ?? ''} onChange={(e) => push('agent', e.target.value)}>
        <option value="">Tous les agents</option>
        {agents.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
      </select>
      <select aria-label="Région" className={sel} value={sp.get('region') ?? ''} onChange={(e) => push('region', e.target.value)}>
        <option value="">Toutes les régions</option>
        {regions.map((r) => <option key={r.id} value={r.id}>{r.name.charAt(0) + r.name.slice(1).toLowerCase()}</option>)}
      </select>
    </div>
  );
}
