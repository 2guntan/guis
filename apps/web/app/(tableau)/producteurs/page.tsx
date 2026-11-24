import type { Metadata } from 'next';
import Link from 'next/link';
import { FilterBar } from '@/components/dashboard/FilterBar';
import { ExportButton, TopBar } from '@/components/dashboard/TopBar';
import { Tag } from '@/components/StatusBadge';
import { fmtDay, fmtHa, fmtNum, fmtPhone } from '@/lib/format';
import { SEXES } from '@/lib/labels';
import { filterOptions, kpis, listProducers } from '@/lib/queries';

export const metadata: Metadata = { title: 'Producteurs' };

// W5 « Producteurs » (docs/design/web/w5-producteurs.png).
export default async function ProducersPage({ searchParams }: { searchParams: Promise<{ q?: string; village?: string; sans?: string }> }) {
  const sp = await searchParams;
  const [all, opts, k] = await Promise.all([listProducers(sp.q), filterOptions(), kpis()]);
  const producers = all.filter((p) => (!sp.village || p.village === sp.village) && (sp.sans !== '1' || p.fields.length === 0));
  return (
    <div>
      <TopBar title="Producteurs">
        <ExportButton />
      </TopBar>
      <FilterBar
        path="/producteurs"
        placeholder="Nom, téléphone ou carte"
        selects={[{ key: 'village', label: 'Tous les villages', options: opts.villages.map((v) => ({ value: v, label: v })) }]}
        check={{ key: 'sans', label: `Sans champ relevé (${k.producers_without_field})` }}
        count={`${producers.length} sur ${k.producers} producteur${k.producers > 1 ? 's' : ''}`}
      />
      <div className="overflow-x-auto border-t border-line">
        <table className="w-full min-w-[1000px] text-[14px]">
          <thead className="bg-[#F4F6F2] text-left text-[13px] text-board-muted">
            <tr>
              <th className="px-6 py-3 font-semibold">Producteur</th>
              <th className="px-3 py-3 font-semibold">Téléphone et carte</th>
              <th className="px-3 py-3 font-semibold">Village</th>
              <th className="px-3 py-3 font-semibold">Semences reçues</th>
              <th className="px-3 py-3 font-semibold">Champs</th>
              <th className="px-6 py-3 font-semibold">Origine</th>
            </tr>
          </thead>
          <tbody className="bg-white">
            {producers.map((p) => {
              const dates = [...new Set(p.seeds.map((s) => s.received_on).filter(Boolean))];
              return (
                <tr key={p.id} className="border-b border-line-soft align-top">
                  <td className="px-6 py-3">
                    <div className="text-[15px] font-semibold" style={{ fontWeight: 650 }}>
                      {p.name}
                    </div>
                    <div className="text-[13px] text-board-muted">{p.sex ? SEXES[p.sex as keyof typeof SEXES] : '—'}</div>
                  </td>
                  <td className="px-3 py-3">
                    <div className="tabular">{fmtPhone(p.phone) || '—'}</div>
                    <div className="text-[13px] text-board-muted">{p.member_card ? `Carte ${p.member_card}` : 'Pas de carte'}</div>
                  </td>
                  <td className="px-3 py-3 font-medium">{p.village ?? '—'}</td>
                  <td className="px-3 py-3">
                    {p.seeds.length === 0 ? (
                      <span className="text-board-muted">Aucune semence</span>
                    ) : (
                      <>
                        <div>{p.seeds.map((s) => `${s.variety} ${fmtNum(s.quantity_kg, 1)} kg`).join(', ')}</div>
                        {dates.length > 0 && (
                          <div className="text-[13px] text-board-muted">
                            {p.seeds.length > 1 ? 'reçues' : 'reçue'} le {dates.map((d) => fmtDay(d)).join(', ')}
                          </div>
                        )}
                      </>
                    )}
                  </td>
                  <td className="px-3 py-3">
                    {p.fields.length === 0 ? (
                      <Tag tone="ochre">Aucun champ relevé</Tag>
                    ) : (
                      <div className="space-y-1">
                        {p.fields.map((f) => (
                          <div key={f.id}>
                            <Link href={`/champs/${f.id}`} className="font-semibold underline underline-offset-4">
                              {f.name ?? 'Champ'}
                            </Link>{' '}
                            {f.area_measured_ha == null ? <span className="text-board-muted">sans contour</span> : fmtHa(f.area_measured_ha)}
                            {f.indicative && (
                              <div className="mt-1">
                                <Tag tone="neutral">Suivi indicatif</Tag>
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </td>
                  <td className="px-6 py-3">
                    <div>{p.source === 'import' ? 'Import du fichier' : `Saisi par ${p.agent_name ?? 'un agent'}`}</div>
                    {!p.consent_at && (
                      <div className="mt-1">
                        <Tag tone="sky">Consentement à recueillir</Tag>
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {producers.length === 0 && (
              <tr>
                <td colSpan={6} className="px-6 py-10 text-center text-board-help">
                  Aucun producteur ne correspond.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
