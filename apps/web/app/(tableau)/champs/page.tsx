import type { Metadata } from 'next';
import Link from 'next/link';
import { FilterBar } from '@/components/dashboard/FilterBar';
import { FieldStatusBadge, Tone } from '@/components/StatusBadge';
import { fmtDate, fmtHa, fmtNum } from '@/lib/format';
import { filterOptions, listFields, type Filters } from '@/lib/queries';

export const metadata: Metadata = { title: 'Champs' };

export default async function FieldsPage({ searchParams }: { searchParams: Promise<Filters> }) {
  const sp = await searchParams;
  const [fields, opts] = await Promise.all([listFields(sp), filterOptions()]);
  const exportQs = new URLSearchParams(Object.entries(sp).filter(([, v]) => typeof v === 'string' && v) as [string, string][]).toString();
  return (
    <main className="mx-auto max-w-7xl space-y-5 px-4 py-6 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl">Champs</h1>
          <p className="text-sm text-ink-soft">{fields.length} champ{fields.length > 1 ? 's' : ''}</p>
        </div>
        <a href={`/export${exportQs ? `?${exportQs}` : ''}`} className="inline-flex h-11 items-center rounded-xl border border-sand-300 bg-surface px-4 text-[15px] font-medium text-forest-800 hover:bg-forest-50">
          Exporter en Excel
        </a>
      </div>
      <FilterBar agents={opts.agents} villages={opts.villages} />
      <div className="panel overflow-x-auto">
        <table className="w-full min-w-[860px] text-sm">
          <thead className="border-b border-sand-200 text-left text-ink-soft">
            <tr>
              <th className="px-4 py-3 font-medium">Producteur</th>
              <th className="px-4 py-3 font-medium">Village</th>
              <th className="px-4 py-3 text-right font-medium">Mesurée</th>
              <th className="px-4 py-3 text-right font-medium">Déclarée</th>
              <th className="px-4 py-3 text-right font-medium">Écart</th>
              <th className="px-4 py-3 font-medium">Semis</th>
              <th className="px-4 py-3 font-medium">Statut</th>
              <th className="px-4 py-3 font-medium">Agent</th>
            </tr>
          </thead>
          <tbody>
            {fields.map((f) => {
              const gap = f.area_measured_ha != null && f.area_declared_ha ? ((f.area_measured_ha - f.area_declared_ha) / f.area_declared_ha) * 100 : null;
              return (
                <tr key={f.id} className="border-b border-sand-100 last:border-0 hover:bg-forest-50/50">
                  <td className="px-4 py-3">
                    <Link href={`/champs/${f.id}`} className="font-medium text-forest-800 hover:underline">{f.producer_name}</Link>
                    <div className="text-xs text-ink-faint">{f.name ?? 'Champ'}</div>
                  </td>
                  <td className="px-4 py-3">{f.village ?? '—'}</td>
                  <td className="px-4 py-3 text-right tabular">{fmtHa(f.area_measured_ha)}</td>
                  <td className="px-4 py-3 text-right tabular">{fmtHa(f.area_declared_ha)}</td>
                  <td className={`px-4 py-3 text-right tabular ${gap != null && Math.abs(gap) > 20 ? 'font-medium text-clay-700' : ''}`}>
                    {gap == null ? '—' : `${gap > 0 ? '+' : ''}${fmtNum(gap, 0)} %`}
                  </td>
                  <td className="px-4 py-3">{fmtDate(f.sown_on)}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1">
                      <FieldStatusBadge status={f.status} />
                      {f.alerts.length > 0 && <Tone tone="clay">{f.alerts.length} alerte{f.alerts.length > 1 ? 's' : ''}</Tone>}
                    </div>
                  </td>
                  <td className="px-4 py-3">{f.agent_name ?? '—'}</td>
                </tr>
              );
            })}
            {fields.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-10 text-center text-ink-faint">Aucun champ ne correspond.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </main>
  );
}
