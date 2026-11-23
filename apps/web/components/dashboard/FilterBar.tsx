'use client';

// Repris de Fieldproof (components/superviseur/FilterBar.tsx) : filtres des champs (village, agent, statut, alerte).
import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Search } from 'lucide-react';
import { FIELD_STATUS } from '@/lib/labels';

export function FilterBar({ agents, villages, path = '/champs' }: { agents: { id: string; name: string }[]; villages: string[]; path?: string }) {
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

  const sel = 'h-11 rounded-xl border border-sand-300 bg-surface px-3 text-sm text-ink focus:border-forest-500 focus:outline-none';
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[1.6fr_1fr_1fr_1fr_auto]">
      <label className="relative">
        <span className="sr-only">Rechercher</span>
        <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-faint" />
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Producteur, téléphone, carte, champ"
          className="h-11 w-full rounded-xl border border-sand-300 bg-surface pl-10 pr-3 text-sm focus:border-forest-500 focus:outline-none"
        />
      </label>
      <select aria-label="Village" className={sel} value={sp.get('village') ?? ''} onChange={(e) => push('village', e.target.value)}>
        <option value="">Tous les villages</option>
        {villages.map((v) => (
          <option key={v} value={v}>{v}</option>
        ))}
      </select>
      <select aria-label="Agent" className={sel} value={sp.get('agent') ?? ''} onChange={(e) => push('agent', e.target.value)}>
        <option value="">Tous les agents</option>
        {agents.map((a) => (
          <option key={a.id} value={a.id}>{a.name}</option>
        ))}
      </select>
      <select aria-label="Statut" className={sel} value={sp.get('statut') ?? ''} onChange={(e) => push('statut', e.target.value)}>
        <option value="">Tous les statuts</option>
        {Object.entries(FIELD_STATUS).map(([k, v]) => (
          <option key={k} value={k}>{v}</option>
        ))}
      </select>
      <label className="flex h-11 items-center gap-2 rounded-xl border border-sand-300 bg-surface px-3 text-sm">
        <input type="checkbox" checked={sp.get('alerte') === '1'} onChange={(e) => push('alerte', e.target.checked ? '1' : '')} />
        En alerte
      </label>
    </div>
  );
}
