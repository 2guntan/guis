import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import NdviChart from '@/components/dashboard/NdviChart';
import { SatellitePasses } from '@/components/dashboard/SatellitePasses';
import { TopBar } from '@/components/dashboard/TopBar';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { StatusPill } from '@/components/StatusBadge';
import { STATUS_FILL } from '@/lib/design';
import { fmtDay, fmtGap, fmtHa, fmtNum, fmtPhone } from '@/lib/format';
import { SEXES } from '@/lib/labels';
import { getField, getProducer, getProducerSeeds, ndviSeries, neighbours } from '@/lib/queries';

// W4 « Fiche champ » (docs/design/web/w4-fiche-champ.png).
export default async function FieldPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const f = await getField(id);
  if (!f) notFound();
  const [producer, seeds, series, around] = await Promise.all([getProducer(f.producer_id), getProducerSeeds(f.producer_id), ndviSeries(f.id), neighbours(f.id)]);
  const gap = fmtGap(f.area_measured_ha, f.area_declared_ha);
  const title = `${f.producer_name}${f.name ? `, ${f.name.charAt(0).toLowerCase()}${f.name.slice(1)}` : ''}`;
  const today = new Date().toISOString().slice(0, 10);
  const alert = f.alerts[0];
  const [alertTitle, ...rest] = alert ? alert.message.split(' : ') : [];
  const alertBody = rest.join(' : ');
  const last = series.filter((p) => p.ndvi !== null).at(-1);
  const rows: [string, React.ReactNode][] = [
    ['Surface mesurée', <strong key="m">{fmtHa(f.area_measured_ha)}</strong>],
    ['Surface déclarée', fmtHa(f.area_declared_ha)],
    ['Écart', gap?.text ?? '—'],
    ['Semis', f.sown_on ? `${fmtDay(f.sown_on)}${f.days_since_sowing != null && f.days_since_sowing >= 0 ? `, J+${f.days_since_sowing}` : ''}` : '—'],
    ['Irrigation', f.irrigation ?? '—'],
    ['Source d’eau', f.water_source ?? '—'],
    ['Contour', f.contour?.length ? `${f.contour.length} sommets, ${fmtNum(f.perimeter_m, 0)} m de tour` : 'À relever'],
  ];
  // Semences reçues : « Spunta 60 kg et Sahel 20 kg reçues le 24/10/2026 ».
  const seedText = seeds.length
    ? `${seeds.map((s) => `${s.variety} ${fmtNum(s.quantity_kg, 1)} kg`).join(', ').replace(/, ([^,]*)$/, ' et $1')} ${seeds.length > 1 ? 'reçues' : 'reçue'}${
        new Set(seeds.map((s) => s.received_on)).size === 1 && seeds[0].received_on ? ` le ${fmtDay(seeds[0].received_on)}` : ''
      }`
    : 'Aucune semence notée';
  return (
    <div>
      <TopBar
        title={title}
        before={
          <Link href="/champs" aria-label="Retour aux champs" className="flex h-10 w-10 items-center justify-center rounded-md border border-line bg-white hover:bg-chalk">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        }
        after={<StatusPill status={f.status} />}
      >
        <span className="text-[14px] text-board-muted">
          {[f.village, f.agent_name && `relevé par ${f.agent_name} le ${fmtDay(f.created_at)}`].filter(Boolean).join(', ')}
        </span>
      </TopBar>
      <div className="grid gap-5 p-6 xl:grid-cols-[380px_1fr]">
        <div className="space-y-5">
          <section className="card-b overflow-hidden">
            <div className="relative">
              {f.geometry ? (
                <>
                  <ParcelsMap
                    className="h-[250px] w-full"
                    interactive={false}
                    parcels={[
                      ...around.map((n) => ({ id: n.id, geometry: n.geometry, fill: STATUS_FILL[n.status], href: `/champs/${n.id}` })),
                      { id: f.id, geometry: f.geometry, fill: STATUS_FILL[f.status] ?? '#D5D8D0', focus: true, inner: f.inner },
                    ]}
                  />
                  <span className="absolute bottom-3 left-3 z-[450] rounded bg-[#163A2C]/85 px-2 py-1 text-[12px] text-white">Pointillés : marge de 5 m retirée</span>
                </>
              ) : (
                <div className="flex h-[250px] items-center justify-center bg-[#E4E5E0] p-6 text-center text-board-muted">
                  Pas encore de contour GPS : l’agent doit faire le tour du champ.
                </div>
              )}
            </div>
            <dl className="px-5 py-1">
              {rows.map(([k, v]) => (
                <div key={k} className="flex justify-between gap-4 border-b border-line-soft py-2.5 text-[14px] last:border-0">
                  <dt className="text-board-muted">{k}</dt>
                  <dd className="tabular text-right">{v}</dd>
                </div>
              ))}
            </dl>
          </section>

          <section className="card-b p-5">
            <h2 className="text-[18px] leading-6">{producer?.name ?? f.producer_name}</h2>
            <p className="mt-2 text-[14px] text-board-muted">
              {[producer?.sex ? SEXES[producer.sex as keyof typeof SEXES] : null, producer?.member_card && `carte ${producer.member_card}`, fmtPhone(producer?.phone)]
                .filter(Boolean)
                .join(', ') || '—'}
            </p>
            <p className="mt-2 text-[14px]">{producer?.consent_at ? `Consentement donné le ${fmtDay(producer.consent_at)}` : 'Consentement à recueillir'}</p>
            <p className="mt-2 text-[14px]">{seedText}</p>
            <Link href={`/producteurs?q=${encodeURIComponent(producer?.name ?? f.producer_name)}`} className="mt-3 inline-block text-[14px] font-semibold underline underline-offset-4">
              Voir ses champs
            </Link>
            {producer?.photo_id && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={`/api/photos/${producer.photo_id}`} alt="Photo du producteur" className="mt-4 h-20 w-20 rounded-md object-cover" />
            )}
          </section>

          {f.photo_id && (
            <section className="card-b p-5">
              <h2 className="text-[18px] leading-6">Photo du champ</h2>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`/api/photos/${f.photo_id}`} alt="Photo du champ" className="mt-3 max-h-72 w-full rounded-md object-cover" />
            </section>
          )}
        </div>

        <div className="space-y-5">
          {alert && (
            <section className="border-l-4 border-alert bg-alert-bg px-5 py-4" role="alert">
              <p className="text-[15px] font-semibold">{alertTitle.replace(/^Chute de NDVI/, 'NDVI en baisse')}</p>
              {alertBody && <p className="mt-1 text-[14px]">{alertBody.charAt(0).toUpperCase() + alertBody.slice(1)}.</p>}
              {f.alerts.length > 1 && <p className="mt-1 text-[13px] text-board-muted">Et {f.alerts.length - 1} autre{f.alerts.length > 2 ? 's' : ''} alerte{f.alerts.length > 2 ? 's' : ''}.</p>}
            </section>
          )}

          <section className="card-b p-5" id="satellite">
            <div className="flex items-baseline justify-between gap-4">
              <h2 className="text-[18px] leading-6">NDVI depuis le semis</h2>
              {last && (
                <span className="text-[14px] text-board-muted">
                  Dernier relevé <span className="display ml-1 text-[32px] text-board-text">{last.ndvi!.toFixed(2).replace('.', ',')}</span>
                </span>
              )}
            </div>
            {series.some((p) => p.ndvi !== null) ? (
              <>
                <div className="mt-3">
                  <NdviChart series={series} sownOn={f.sown_on} today={today} dropAlert={f.alerts.some((a) => a.code === 'ndvi_drop')} />
                </div>
                <div className="mt-2 flex flex-wrap gap-5 text-[13px] text-board-muted">
                  <span className="inline-flex items-center gap-2">
                    <span className="h-0.5 w-5 bg-board-text" /> NDVI mesuré sur le champ
                  </span>
                  {f.sown_on && (
                    <span className="inline-flex items-center gap-2">
                      <span className="h-3 w-5 bg-[#A9C47F]/50" /> Plage attendue pour la pomme de terre
                    </span>
                  )}
                  {f.indicative && <span>Suivi indicatif : champ trop petit pour Sentinel-2.</span>}
                </div>
              </>
            ) : (
              <p className="mt-3 text-[14px] text-board-muted">
                {f.status === 'none' ? 'Le suivi commence dès que le contour du champ est relevé.' : 'En attente des premières images Sentinel-2.'}
              </p>
            )}
          </section>

          {series.length > 0 && f.geometry != null && (
            <section className="card-b p-5">
              <h2 className="mb-4 text-[18px] leading-6">Le champ à chaque passage du satellite</h2>
              <SatellitePasses geometry={f.geometry} series={series} />
            </section>
          )}
        </div>
      </div>
    </div>
  );
}
