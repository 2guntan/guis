import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { FieldStatusBadge, STATUS_COLOR, Tone } from '@/components/StatusBadge';
import { fmtDate, fmtDateTime, fmtHa, fmtNum } from '@/lib/format';
import { SEXES } from '@/lib/labels';
import { getField, getProducer, getProducerSeeds } from '@/lib/queries';

export default async function FieldPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const f = await getField(id);
  if (!f) notFound();
  const [producer, seeds] = await Promise.all([getProducer(f.producer_id), getProducerSeeds(f.producer_id)]);
  const gap = f.area_measured_ha != null && f.area_declared_ha ? ((f.area_measured_ha - f.area_declared_ha) / f.area_declared_ha) * 100 : null;
  const rows: [string, React.ReactNode][] = [
    ['Surface mesurée (GPS)', fmtHa(f.area_measured_ha)],
    ['Surface déclarée', fmtHa(f.area_declared_ha)],
    ['Écart', gap == null ? '—' : `${gap > 0 ? '+' : ''}${fmtNum(gap, 0)} %`],
    ['Date de semis', fmtDate(f.sown_on)],
    ['Irrigation', f.irrigation ?? '—'],
    ['Source d’eau', f.water_source ?? '—'],
    ['Sommets du contour', f.contour?.length ? String(f.contour.length) : '—'],
    ['Relevé par', f.agent_name ?? '—'],
    ['Relevé le', fmtDateTime(f.created_at)],
  ];
  return (
    <main className="mx-auto max-w-7xl space-y-5 px-4 py-6 sm:px-6">
      <div>
        <Link href="/champs" className="text-sm text-ink-soft hover:underline">← Champs</Link>
        <div className="mt-1 flex flex-wrap items-center gap-3">
          <h1 className="text-3xl">{f.producer_name}</h1>
          <FieldStatusBadge status={f.status} />
        </div>
        <p className="text-sm text-ink-soft">{[f.name, f.village].filter(Boolean).join(' · ')}</p>
      </div>
      <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
        <section className="panel overflow-hidden">
          {f.geometry ? (
            <ParcelsMap className="h-[420px] w-full" parcels={[{ id: f.id, geometry: f.geometry, color: STATUS_COLOR[f.status], label: fmtHa(f.area_measured_ha) }]} />
          ) : (
            <div className="flex h-[420px] items-center justify-center p-6 text-center text-ink-faint">Pas encore de contour GPS : l’agent doit faire le tour du champ.</div>
          )}
        </section>
        <section className="panel p-5">
          <h2 className="text-xl">Champ</h2>
          <dl className="mt-3 divide-y divide-sand-100 text-sm">
            {rows.map(([k, v]) => (
              <div key={k} className="flex justify-between gap-4 py-2">
                <dt className="text-ink-soft">{k}</dt>
                <dd className="text-right font-medium tabular">{v}</dd>
              </div>
            ))}
          </dl>
        </section>
      </div>

      <section className="panel p-5" id="satellite">
        <h2 className="text-xl">Suivi satellite</h2>
        {f.alerts.length > 0 && (
          <ul className="mt-3 space-y-2">
            {f.alerts.map((a) => (
              <li key={a.code}><Tone tone="clay">{a.message}</Tone></li>
            ))}
          </ul>
        )}
        <p className="mt-3 text-sm text-ink-soft">
          {f.status === 'none'
            ? 'Le suivi commence dès que le contour du champ est relevé.'
            : f.last_ndvi == null
              ? 'En attente des premières images Sentinel-2.'
              : `Dernier NDVI : ${fmtNum(f.last_ndvi, 2)}${f.indicative ? ' (suivi indicatif : champ trop petit pour Sentinel-2)' : ''}.`}
        </p>
      </section>

      <div className="grid gap-5 lg:grid-cols-2">
        <section className="panel p-5">
          <h2 className="text-xl">Producteur</h2>
          <div className="mt-3 flex gap-4">
            {producer?.photo_id && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={`/api/photos/${producer.photo_id}`} alt="Photo du producteur" className="h-24 w-24 rounded-xl object-cover" />
            )}
            <dl className="text-sm">
              <div>{f.phone ?? 'Sans téléphone'}</div>
              <div>{f.member_card ? `Carte de membre ${f.member_card}` : 'Sans carte de membre'}</div>
              <div>{producer?.sex ? SEXES[producer.sex as keyof typeof SEXES] : ''}</div>
              <div className="text-ink-soft">{producer?.consent_at ? `Consentement le ${fmtDateTime(producer.consent_at)}` : 'Consentement à recueillir'}</div>
            </dl>
          </div>
          <h3 className="mt-5 text-base font-semibold">Semences reçues</h3>
          {seeds.length === 0 ? (
            <p className="text-sm text-ink-faint">Aucune semence notée.</p>
          ) : (
            <ul className="mt-1 text-sm">
              {seeds.map((s, i) => (
                <li key={i}>{s.variety} — {fmtNum(s.quantity_kg, 1)} kg{s.received_on ? `, reçue le ${fmtDate(s.received_on)}` : ''}</li>
              ))}
            </ul>
          )}
        </section>
        <section className="panel p-5">
          <h2 className="text-xl">Photo du champ</h2>
          {f.photo_id ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={`/api/photos/${f.photo_id}`} alt="Photo du champ" className="mt-3 max-h-80 w-full rounded-xl object-cover" />
          ) : (
            <p className="mt-3 text-sm text-ink-faint">Pas de photo.</p>
          )}
        </section>
      </div>
    </main>
  );
}
