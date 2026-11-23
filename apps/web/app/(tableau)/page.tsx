import Link from 'next/link';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { STATUS_COLOR } from '@/components/StatusBadge';
import { fmtHa, fmtNum } from '@/lib/format';
import { FIELD_STATUS, type FieldStatus } from '@/lib/labels';
import { kpis, listFields } from '@/lib/queries';

export default async function Home() {
  const [k, fields] = await Promise.all([kpis(), listFields()]);
  const counts = new Map<FieldStatus, number>();
  for (const f of fields) counts.set(f.status, (counts.get(f.status) ?? 0) + 1);
  const gap = k.declared_ha > 0 ? ((k.measured_ha - k.declared_ha) / k.declared_ha) * 100 : null;
  const cards = [
    { label: 'Producteurs', value: fmtNum(k.producers, 0), hint: `${fmtNum(k.producers_without_field, 0)} sans champ relevé`, href: '/producteurs' },
    { label: 'Champs relevés', value: fmtNum(k.fields, 0), hint: `${fmtNum(k.fields_with_contour, 0)} avec contour GPS`, href: '/champs' },
    { label: 'Surface mesurée', value: fmtHa(k.measured_ha), hint: `déclarée : ${fmtHa(k.declared_ha)}${gap === null ? '' : ` (écart ${gap > 0 ? '+' : ''}${fmtNum(gap, 0)} %)`}` },
    { label: 'Semences distribuées', value: `${fmtNum(k.seeds_kg, 0)} kg` },
    { label: 'Champs en alerte', value: fmtNum(k.alerts, 0), hint: 'à vérifier sur le terrain', href: '/champs?alerte=1', alert: k.alerts > 0 },
  ];
  return (
    <main className="mx-auto max-w-7xl space-y-6 px-4 py-6 sm:px-6">
      <h1 className="text-3xl">Tableau de bord</h1>
      <section className="grid grid-cols-2 gap-3 lg:grid-cols-5" aria-label="Chiffres clés">
        {cards.map((c) => {
          const body = (
            <div className={`panel h-full p-4 ${c.alert ? 'border-clay-500/50' : ''}`}>
              <div className="eyebrow">{c.label}</div>
              <div className={`mt-1 font-display text-3xl tabular ${c.alert ? 'text-clay-700' : 'text-forest-900'}`}>{c.value}</div>
              {c.hint && <div className="mt-1 text-xs text-ink-faint">{c.hint}</div>}
            </div>
          );
          return c.href ? <Link key={c.label} href={c.href} className="block">{body}</Link> : <div key={c.label}>{body}</div>;
        })}
      </section>
      <section className="panel overflow-hidden">
        <ParcelsMap
          className="h-[60vh] min-h-80 w-full"
          parcels={fields
            .filter((f) => f.geometry)
            .map((f) => ({ id: f.id, geometry: f.geometry, label: `${f.producer_name}${f.name ? ` — ${f.name}` : ''}`, color: STATUS_COLOR[f.status], href: `/champs/${f.id}` }))}
        />
        <div className="flex flex-wrap gap-x-4 gap-y-1 px-4 py-3 text-xs text-ink-soft">
          {(Object.keys(FIELD_STATUS) as FieldStatus[]).map((s) => (
            <span key={s} className="inline-flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-sm" style={{ background: STATUS_COLOR[s] }} />
              {FIELD_STATUS[s]} ({counts.get(s) ?? 0})
            </span>
          ))}
        </div>
      </section>
    </main>
  );
}
