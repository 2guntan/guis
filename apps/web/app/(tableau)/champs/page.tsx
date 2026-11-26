import type { Metadata } from 'next';
import Link from 'next/link';
import { FilterBar } from '@/components/dashboard/FilterBar';
import { Sparkline } from '@/components/dashboard/Sparkline';
import { Pagination, rangeLabel } from '@/components/dashboard/Pagination';
import { ExportButton, TopBar } from '@/components/dashboard/TopBar';
import { requireDashboard } from '@/lib/auth';
import { can } from '@/lib/rights';
import { StatusMark, Tag } from '@/components/StatusBadge';
import { STATUS_ORDER, STATUS_SHORT, alertTag } from '@/lib/design';
import { fmtDay, fmtGap, fmtHa } from '@/lib/format';
import { filterOptions, kpis, listFieldsPage, PAGE_SIZE, pageNumber, sparkSeries, type Filters } from '@/lib/queries';

export const metadata: Metadata = { title: 'Champs' };

// W3 « Champs » (docs/design/web/w3-champs.png).
export default async function FieldsPage({ searchParams }: { searchParams: Promise<Filters & { page?: string }> }) {
  const sp = await searchParams;
  const user = await requireDashboard();
  const [list, opts, k] = await Promise.all([listFieldsPage(sp, pageNumber(sp.page)), filterOptions(), kpis()]);
  const fields = list.rows;
  const sparks = await sparkSeries(fields.map((f) => f.id));
  const exportQs = new URLSearchParams(Object.entries(sp).filter(([key, v]) => key !== 'page' && typeof v === 'string' && v) as [string, string][]).toString();
  return (
    <div>
      <TopBar title="Champs">
        {can(user, 'export') && <ExportButton href={`/api/export${exportQs ? `?${exportQs}` : ''}`} />}
      </TopBar>
      <FilterBar
        path="/champs"
        placeholder="Producteur ou champ"
        selects={[
          { key: 'village', label: 'Tous les villages', options: opts.villages.map((v) => ({ value: v, label: v })) },
          { key: 'agent', label: 'Tous les agents', options: opts.agents.map((a) => ({ value: a.id, label: a.name })) },
          { key: 'statut', label: 'Tous les statuts', options: STATUS_ORDER.map((s) => ({ value: s, label: STATUS_SHORT[s] })) },
        ]}
        check={{ key: 'alerte', label: `À vérifier seulement (${k.alerts})` }}
        count={rangeLabel(list.page, PAGE_SIZE, list.total, ['champ', 'champs'])}
      />
      <div className="overflow-x-auto border-t border-line">
        <table className="w-full min-w-[1080px] text-[14px]">
          <thead className="bg-[#F4F6F2] text-left text-[13px] text-board-muted">
            <tr>
              <th className="px-6 py-3 font-semibold">Producteur et champ</th>
              <th className="px-3 py-3 font-semibold">Village</th>
              <th className="px-3 py-3 font-semibold">Mesurée</th>
              <th className="px-3 py-3 font-semibold">Déclarée</th>
              <th className="px-3 py-3 font-semibold">Écart</th>
              <th className="px-3 py-3 font-semibold">Semis</th>
              <th className="px-3 py-3 font-semibold">Courbe NDVI</th>
              <th className="px-3 py-3 font-semibold">Statut</th>
              <th className="px-6 py-3 font-semibold">Agent</th>
            </tr>
          </thead>
          <tbody className="bg-white">
            {fields.map((f) => {
              const gap = fmtGap(f.area_measured_ha, f.area_declared_ha);
              const alert = f.alerts.length > 0;
              return (
                <tr key={f.id} className={`border-b border-line-soft ${alert ? 'bg-alert-bg/70 [&>td:first-child]:border-l-4 [&>td:first-child]:border-l-alert' : ''}`}>
                  <td className="px-6 py-2.5">
                    <Link href={`/champs/${f.id}`} className="text-[15px] font-semibold hover:underline" style={{ fontWeight: 650 }}>
                      {f.producer_name}
                    </Link>
                    <div className="text-[13px] text-board-muted">{f.name ?? 'Champ'}</div>
                  </td>
                  <td className="px-3 py-2.5">{f.village ?? '—'}</td>
                  <td className="tabular px-3 py-2.5">{fmtHa(f.area_measured_ha)}</td>
                  <td className="tabular px-3 py-2.5">{fmtHa(f.area_declared_ha)}</td>
                  <td className={`tabular px-3 py-2.5 ${gap && Math.abs(gap.value) > 20 ? 'font-semibold text-[#8A5F14]' : ''}`}>{gap?.text ?? '—'}</td>
                  <td className="tabular px-3 py-2.5">{fmtDay(f.sown_on)}</td>
                  <td className="px-3 py-2.5">
                    <Sparkline values={sparks[f.id] ?? []} alert={f.alerts.some((a) => a.code === 'ndvi_drop')} />
                  </td>
                  <td className="px-3 py-2.5">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <StatusMark status={f.status} />
                      {f.alerts.map((a) => (
                        <Tag key={a.code} tone="alert">
                          {alertTag(a)}
                        </Tag>
                      ))}
                      {f.indicative && <Tag tone="neutral">Suivi indicatif</Tag>}
                    </div>
                  </td>
                  <td className="px-6 py-2.5">{f.agent_name ?? '—'}</td>
                </tr>
              );
            })}
            {fields.length === 0 && (
              <tr>
                <td colSpan={9} className="px-6 py-10 text-center text-board-help">
                  Aucun champ ne correspond.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <Pagination path="/champs" search={sp} page={list.page} pages={list.pages} />
    </div>
  );
}
