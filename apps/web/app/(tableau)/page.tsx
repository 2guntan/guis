import Link from 'next/link';
import { Search } from 'lucide-react';
import { ExportButton, TopBar } from '@/components/dashboard/TopBar';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { STATUS_FILL, STATUS_ORDER, STATUS_SHORT, alertSentence, campaignLabel } from '@/lib/design';
import { fmtDM, fmtDay, fmtGap, fmtHa, fmtNum } from '@/lib/format';
import type { FieldStatus } from '@/lib/labels';
import { countDuplicates } from '@/lib/duplicates';
import { kpis, listFields, sceneDates } from '@/lib/queries';

// W2 « Carte » (docs/design/web/w2-carte.png) : carte de tous les champs, panneau des chiffres et des champs à vérifier.
export default async function MapPage() {
  const [k, fields, scenes, duplicates] = await Promise.all([kpis(), listFields(), sceneDates(6), countDuplicates()]);
  const counts = new Map<FieldStatus, number>();
  for (const f of fields) counts.set(f.status, (counts.get(f.status) ?? 0) + 1);
  const toCheck = fields.filter((f) => f.alerts.length > 0);
  const gap = fmtGap(k.measured_ha, k.declared_ha);
  const last = scenes.filter((s) => s.clear).at(-1)?.date;
  return (
    <div className="flex h-dvh flex-col">
      <TopBar title={campaignLabel()}>
        <form action="/champs" className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-board-help" />
          <input name="q" placeholder="Producteur, champ ou village" aria-label="Rechercher un champ" className="input-b w-[260px] pl-9" />
        </form>
        <ExportButton />
      </TopBar>
      <div className="flex min-h-0 flex-1">
        <section className="relative min-w-0 flex-1" aria-label="Carte des champs">
          <ParcelsMap
            className="h-full w-full"
            parcels={fields
              .filter((f) => f.geometry)
              .map((f) => ({
                id: f.id,
                geometry: f.geometry,
                fill: STATUS_FILL[f.status],
                alert: f.alerts.length > 0,
                href: `/champs/${f.id}`,
                label: `${f.producer_name}${f.name ? `, ${f.name}` : ''} · ${STATUS_SHORT[f.status]}`,
              }))}
          />
          {scenes.length > 0 && (
            <div className="absolute inset-x-4 bottom-4 z-[400] rounded-lg bg-white/95 px-5 py-3 shadow-md">
              <div className="flex items-baseline justify-between gap-4 text-[14px]">
                <span className="font-semibold">Images Sentinel-2 depuis les premiers semis</span>
                {last && <span className="text-[13px] text-board-help">Affichée : {fmtDay(last)}, la plus récente</span>}
              </div>
              <ol className="relative mt-3 flex justify-between">
                <span aria-hidden className="absolute left-2 right-2 top-[7px] h-0.5 bg-board-text" />
                {scenes.map((s) => (
                  <li key={s.date} className="relative flex flex-col items-center gap-1 text-[13px]">
                    <span
                      className={`h-4 w-4 rounded-full border-2 ${
                        s.date === last ? 'border-alert bg-board-text ring-2 ring-alert' : s.clear ? 'border-board-text bg-board-text' : 'border-board-text bg-white'
                      }`}
                    />
                    <span className={s.clear ? 'font-semibold' : 'text-board-help'}>
                      {fmtDM(s.date)}
                      {!s.clear && ' nuages'}
                    </span>
                  </li>
                ))}
              </ol>
            </div>
          )}
        </section>

        <aside className="flex w-[360px] shrink-0 flex-col overflow-y-auto border-l border-line bg-white" aria-label="Chiffres et champs à vérifier">
          <div className="border-b border-line px-6 py-5">
            <div className="flex items-baseline gap-3">
              <span className="display text-[40px] leading-[44px] text-board-text">{fmtNum(k.fields, 0)}</span>
              <span className="text-[14px] text-board-muted">champs relevés, {fmtHa(k.measured_ha).replace(/,00 ha$/, ' ha')}</span>
            </div>
            <div className="mt-3 flex h-3 w-full overflow-hidden rounded-sm" aria-hidden>
              {STATUS_ORDER.map((s) =>
                counts.get(s) ? (
                  <span
                    key={s}
                    style={{
                      flexGrow: counts.get(s),
                      background: STATUS_FILL[s] ?? 'repeating-linear-gradient(135deg,#163A2C 0 2px,#fff 2px 4px)',
                    }}
                    className="ml-px first:ml-0"
                  />
                ) : null,
              )}
            </div>
            <ul className="mt-3 space-y-1 text-[13px]">
              {STATUS_ORDER.map((s) => (
                <li key={s} className="flex items-center gap-2">
                  <span
                    className="h-3 w-3 rounded-[3px]"
                    style={STATUS_FILL[s] ? { background: STATUS_FILL[s]! } : { border: '1.5px dashed #163A2C' }}
                  />
                  <Link href={`/champs?statut=${s}`} className="flex-1 hover:underline">
                    {STATUS_SHORT[s]}
                  </Link>
                  <span className="tabular font-semibold">{counts.get(s) ?? 0}</span>
                </li>
              ))}
            </ul>
            <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 border-t border-line-soft pt-3 text-[13px]">
              <div>
                <dt className="text-board-help">Producteurs</dt>
                <dd className="font-semibold">
                  {fmtNum(k.producers, 0)} <span className="font-normal text-board-muted">dont {fmtNum(k.producers_without_field, 0)} sans champ</span>
                </dd>
              </div>
              <div>
                <dt className="text-board-help">Semences distribuées</dt>
                <dd className="font-semibold">{fmtNum(k.seeds_kg, 0)} kg</dd>
              </div>
              {duplicates > 0 && (
                <div className="col-span-2">
                  <dt className="text-board-help">Doublons possibles</dt>
                  <dd className="font-semibold">
                    <Link href="/doublons" className="underline underline-offset-4">
                      {fmtNum(duplicates, 0)} à trancher
                    </Link>
                  </dd>
                </div>
              )}
              <div className="col-span-2">
                <dt className="text-board-help">Surface déclarée</dt>
                <dd className="font-semibold">
                  {fmtHa(k.declared_ha)} {gap && <span className="font-normal text-board-muted">(écart avec la mesure : {gap.text})</span>}
                </dd>
              </div>
            </dl>
          </div>

          <div className="flex items-baseline justify-between px-6 pb-2 pt-5">
            <h2 className="text-[18px] leading-6">
              {toCheck.length} champ{toCheck.length > 1 ? 's' : ''} à vérifier
            </h2>
            {last && <span className="text-[13px] text-board-help">Image du {fmtDM(last)}</span>}
          </div>
          <ul>
            {toCheck.length === 0 && <li className="px-6 pb-6 text-[14px] text-board-help">Aucun champ en alerte.</li>}
            {toCheck.map((f, i) => (
              <li key={f.id} className={`border-t border-line-soft ${i === 0 ? 'border-l-4 border-l-alert bg-alert-bg' : ''}`}>
                <Link href={`/champs/${f.id}`} className="block px-6 py-3 hover:bg-chalk">
                  <div className="text-[15px] font-semibold" style={{ fontWeight: 650 }}>
                    {f.producer_name}
                    {f.name ? `, ${f.name.toLowerCase()}` : ''}
                  </div>
                  <p className="mt-1 text-[14px] leading-[19px]">
                    {alertSentence(f.alerts[0])}
                    {f.indicative && ` Champ de ${fmtHa(f.area_measured_ha)} : suivi indicatif.`}
                  </p>
                  <p className="mt-1 text-[13px] text-board-help">
                    {[f.village, f.agent_name && `relevé par ${f.agent_name}`].filter(Boolean).join(', ')}
                  </p>
                </Link>
              </li>
            ))}
          </ul>
        </aside>
      </div>
    </div>
  );
}
