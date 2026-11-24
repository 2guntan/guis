import type { Metadata } from 'next';
import Link from 'next/link';
import { FilterBar } from '@/components/dashboard/FilterBar';
import { ExportButton, TopBar } from '@/components/dashboard/TopBar';
import { Tag } from '@/components/StatusBadge';
import { fmtDay, fmtGap, fmtHa, fmtNum, fmtPhone } from '@/lib/format';
import { SEXES } from '@/lib/labels';
import { filterOptions, kpis, listProducers } from '@/lib/queries';

export const metadata: Metadata = { title: 'Producteurs' };

// W5 « Producteurs » (docs/design/web/w5-producteurs.png).
const NOM_A_COMPLETER = 'À COMPLÉTER';
const toComplete = (p: { last_name: string; phone: string | null }) => p.last_name === NOM_A_COMPLETER || !p.phone;

type Search = { q?: string; village?: string; commune?: string; sans?: string; completer?: string; doublon?: string };

export default async function ProducersPage({ searchParams }: { searchParams: Promise<Search> }) {
  const sp = await searchParams;
  const [all, opts, k] = await Promise.all([listProducers(sp.q), filterOptions(), kpis()]);
  const producers = all.filter(
    (p) =>
      (!sp.village || p.village === sp.village) &&
      (!sp.commune || p.commune === sp.commune) &&
      (sp.sans !== '1' || p.fields.length === 0) &&
      (sp.completer !== '1' || toComplete(p)) &&
      (sp.doublon !== '1' || p.possible_duplicate),
  );
  const nComplete = all.filter(toComplete).length;
  const nDup = all.filter((p) => p.possible_duplicate).length;
  return (
    <div>
      <TopBar title="Producteurs">
        <ExportButton />
      </TopBar>
      <FilterBar
        path="/producteurs"
        placeholder="Nom, téléphone, carte ou commune"
        selects={[
          { key: 'commune', label: 'Toutes les communes', options: opts.communes.map((v) => ({ value: v, label: v })) },
          { key: 'village', label: 'Tous les villages', options: opts.villages.map((v) => ({ value: v, label: v })) },
        ]}
        checks={[
          { key: 'sans', label: `Sans champ relevé (${k.producers_without_field})` },
          { key: 'completer', label: `À compléter (${nComplete})` },
          ...(nDup ? [{ key: 'doublon', label: `Doublons possibles (${nDup})` }] : []),
        ]}
        count={`${producers.length} sur ${k.producers} producteur${k.producers > 1 ? 's' : ''}`}
      />
      <div className="overflow-x-auto border-t border-line">
        <table className="w-full min-w-[1160px] text-[14px]">
          <thead className="bg-[#F4F6F2] text-left text-[13px] text-board-muted">
            <tr>
              <th className="px-6 py-3 font-semibold">Producteur</th>
              <th className="px-3 py-3 font-semibold">Téléphone et carte</th>
              <th className="px-3 py-3 font-semibold">Village et commune</th>
              <th className="px-3 py-3 font-semibold">Surfaces</th>
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
                  <td className="px-3 py-3">
                    <div className="font-medium">{p.village ?? '—'}</div>
                    <div className="text-[13px] text-board-muted">{p.commune ?? 'Sans commune'}</div>
                  </td>
                  <td className="px-3 py-3">
                    <Surfaces p={p} />
                  </td>
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
                    {p.fields.length > 1 && <div className="text-[13px] text-board-muted">{p.fields.length} champs</div>}
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
                    {toComplete(p) && (
                      <div className="mt-1">
                        <Tag tone="ochre">{p.phone ? 'Nom à compléter' : 'Téléphone à compléter'}</Tag>
                      </div>
                    )}
                    {p.possible_duplicate && (
                      <div className="mt-1">
                        <Link href="/doublons">
                          <Tag tone="alert">Doublon possible</Tag>
                        </Link>
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
            {producers.length === 0 && (
              <tr>
                <td colSpan={7} className="px-6 py-10 text-center text-board-help">
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

/** Surface déclarée et validée (fiche de la coopérative) face à la somme des surfaces mesurées des champs. */
function Surfaces({ p }: { p: { area_declared_ha: number | null; area_validated_ha: number | null; area_measured_ha: number | null } }) {
  const gap = fmtGap(p.area_measured_ha, p.area_validated_ha);
  const line = (label: string, v: number | null) => (
    <div className="flex justify-between gap-3">
      <span className="text-board-muted">{label}</span>
      <span className="tabular">{v == null ? '—' : fmtHa(v)}</span>
    </div>
  );
  return (
    <div className="min-w-[170px] text-[13px]">
      {line('Déclarée', p.area_declared_ha)}
      {line('Validée', p.area_validated_ha)}
      {line('Mesurée', p.area_measured_ha)}
      {gap && <div className="mt-0.5 text-right text-board-help">écart mesurée / validée : {gap.text}</div>}
    </div>
  );
}
