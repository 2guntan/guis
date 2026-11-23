import type { Metadata } from 'next';
import Link from 'next/link';
import { Tone } from '@/components/StatusBadge';
import { fmtHa, fmtNum } from '@/lib/format';
import { listProducers } from '@/lib/queries';

export const metadata: Metadata = { title: 'Producteurs' };

export default async function ProducersPage({ searchParams }: { searchParams: Promise<{ q?: string; sans?: string }> }) {
  const sp = await searchParams;
  let producers = await listProducers(sp.q);
  if (sp.sans === '1') producers = producers.filter((p) => p.fields.length === 0);
  return (
    <main className="mx-auto max-w-7xl space-y-5 px-4 py-6 sm:px-6">
      <div>
        <h1 className="text-3xl">Producteurs</h1>
        <p className="text-sm text-ink-soft">{producers.length} producteur{producers.length > 1 ? 's' : ''}</p>
      </div>
      <form className="flex flex-wrap gap-3" action="/producteurs">
        <input name="q" defaultValue={sp.q ?? ''} placeholder="Nom, téléphone, carte, village" className="h-11 w-full max-w-sm rounded-xl border border-sand-300 bg-surface px-3 text-sm focus:border-forest-500 focus:outline-none" />
        <label className="flex h-11 items-center gap-2 rounded-xl border border-sand-300 bg-surface px-3 text-sm">
          <input type="checkbox" name="sans" value="1" defaultChecked={sp.sans === '1'} /> Sans champ relevé
        </label>
        <button className="h-11 rounded-xl bg-forest-800 px-4 text-sm font-medium text-paper">Filtrer</button>
      </form>
      <div className="panel overflow-x-auto">
        <table className="w-full min-w-[820px] text-sm">
          <thead className="border-b border-sand-200 text-left text-ink-soft">
            <tr>
              <th className="px-4 py-3 font-medium">Producteur</th>
              <th className="px-4 py-3 font-medium">Village</th>
              <th className="px-4 py-3 font-medium">Semences</th>
              <th className="px-4 py-3 font-medium">Champs</th>
              <th className="px-4 py-3 font-medium">Origine</th>
            </tr>
          </thead>
          <tbody>
            {producers.map((p) => (
              <tr key={p.id} className="border-b border-sand-100 align-top last:border-0">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {p.photo_id ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={`/api/photos/${p.photo_id}`} alt="" className="h-9 w-9 rounded-full object-cover" />
                    ) : (
                      <span className="h-9 w-9 rounded-full bg-sand-100" />
                    )}
                    <div>
                      <div className="font-medium">{p.name}</div>
                      <div className="text-xs text-ink-faint">{[p.phone, p.member_card && `Carte ${p.member_card}`].filter(Boolean).join(' · ') || '—'}</div>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">{p.village ?? '—'}</td>
                <td className="px-4 py-3">
                  {p.seeds.length === 0 ? '—' : p.seeds.map((s, i) => <div key={i}>{s.variety} : {fmtNum(s.quantity_kg, 1)} kg</div>)}
                </td>
                <td className="px-4 py-3">
                  {p.fields.length === 0 ? (
                    <Tone tone="ochre">Aucun champ relevé</Tone>
                  ) : (
                    p.fields.map((f) => (
                      <div key={f.id}>
                        <Link href={`/champs/${f.id}`} className="text-forest-800 hover:underline">{f.name ?? 'Champ'}</Link> {fmtHa(f.area_measured_ha)}
                      </div>
                    ))
                  )}
                </td>
                <td className="px-4 py-3">
                  {p.source === 'import' ? <Tone tone="sky">Import</Tone> : <span className="text-ink-soft">{p.agent_name ?? 'App'}</span>}
                  {!p.consent_at && <div className="mt-1"><Tone tone="neutral">Consentement à recueillir</Tone></div>}
                </td>
              </tr>
            ))}
            {producers.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-10 text-center text-ink-faint">Aucun producteur.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </main>
  );
}
