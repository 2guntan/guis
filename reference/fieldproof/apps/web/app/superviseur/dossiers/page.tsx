import type { Metadata } from 'next';
import Link from 'next/link';
import { Suspense } from 'react';
import { requireRole } from '@/lib/session';
import { FileStatusBadge, PackageBadge } from '@/components/StatusBadge';
import { FilterBar } from '@/components/superviseur/FilterBar';
import { cleanName, fmtHa, fmtXof, relTime } from '@/lib/format';
import { PACKAGE_KIND, type FileStatus, type PackageKind } from '@/lib/labels';

export const metadata: Metadata = { title: 'Dossiers' };
export const dynamic = 'force-dynamic';

type Row = {
  id: string; reference: string; status: FileStatus; client_name: string | null; client_phone: string | null; agent_id: string | null; agent_name: string | null;
  region_name: string | null; commune_name: string | null; locality: string | null; branch_name: string | null; updated_at: string;
  credit_amount_xof: number | null; wants_credit: boolean; wants_account_opening: boolean; total_gps_area_ha: number | null; return_reason: string | null;
  packages: { id: string; kind: PackageKind; generation_status: string; lender_status: string | null }[] | null;
};

export default async function Files({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const s = await requireRole('supervisor');
  const db = s.supabase;
  let query = db.schema('dossier').from('file_overview')
    .select('id, reference, status, client_name, client_phone, agent_id, agent_name, region_name, commune_name, locality, branch_name, updated_at, credit_amount_xof, wants_credit, wants_account_opening, total_gps_area_ha, return_reason, packages')
    .order('updated_at', { ascending: false }).limit(300);
  if (sp.statut) query = query.eq('status', sp.statut);
  if (sp.agent) query = query.eq('agent_id', sp.agent);
  if (sp.region) query = query.eq('region_id', sp.region);
  if (sp.q) {
    const q = sp.q.replace(/[%,()]/g, ' ').trim();
    if (q) query = query.or(`client_name.ilike.%${q}%,reference.ilike.%${q}%,client_phone.ilike.%${q.replace(/\s/g, '')}%`);
  }
  const [{ data, error }, agentsQ, regionsQ] = await Promise.all([
    query,
    db.schema('dossier').from('file_overview').select('agent_id, agent_name'),
    db.schema('core').from('geo_regions').select('id, name').order('name'),
  ]);
  const rows = (data ?? []) as Row[];
  const agents = Array.from(new Map(((agentsQ.data ?? []) as { agent_id: string; agent_name: string }[]).filter((a) => a.agent_id).map((a) => [a.agent_id, { id: a.agent_id, name: cleanName(a.agent_name) }])).values());

  return (
    <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6">
      <h1 className="text-[36px] leading-tight">Dossiers clients</h1>
      <p className="mt-1 text-sm text-ink-soft">{rows.length} dossier{rows.length > 1 ? 's' : ''}{sp.statut || sp.agent || sp.region || sp.q ? ' correspondant aux filtres' : ''}</p>
      <div className="mt-6"><Suspense><FilterBar agents={agents} regions={(regionsQ.data ?? []) as { id: string; name: string }[]} /></Suspense></div>
      {error && <p className="mt-4 rounded-xl bg-clay-50 px-4 py-3 text-sm text-clay-700">{error.message}</p>}

      <div className="panel mt-6 overflow-hidden">
        <table className="hidden w-full text-left text-sm md:table">
          <thead className="border-b border-sand-200 bg-sand-100/60 text-xs text-ink-soft">
            <tr>
              <th className="px-5 py-3 font-medium">Client</th>
              <th className="px-3 py-3 font-medium">Statut</th>
              <th className="px-3 py-3 font-medium">Agent terrain</th>
              <th className="px-3 py-3 font-medium">Localité</th>
              <th className="px-3 py-3 text-right font-medium">Demande</th>
              <th className="px-3 py-3 font-medium">Paquets</th>
              <th className="px-5 py-3 text-right font-medium">Modifié</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-sand-200">
            {rows.map((r) => (
              <tr key={r.id} className="group relative hover:bg-sand-100/50">
                <td className="px-5 py-3.5">
                  <Link href={`/superviseur/dossiers/${r.id}`} className="font-display text-[17px] text-forest-900 after:absolute after:inset-0">{r.client_name || 'Client sans nom'}</Link>
                  <div className="text-xs tabular text-ink-faint">{r.reference}</div>
                </td>
                <td className="px-3 py-3.5"><FileStatusBadge status={r.status} /></td>
                <td className="px-3 py-3.5 text-ink-soft">{cleanName(r.agent_name)}</td>
                <td className="px-3 py-3.5 text-ink-soft">{r.locality || r.commune_name || '—'}<div className="text-xs text-ink-faint">{r.region_name ? r.region_name.charAt(0) + r.region_name.slice(1).toLowerCase() : ''}</div></td>
                <td className="px-3 py-3.5 text-right tabular">{r.wants_credit ? fmtXof(r.credit_amount_xof) : 'Compte'}<div className="text-xs text-ink-faint">{fmtHa(r.total_gps_area_ha)}</div></td>
                <td className="px-3 py-3.5">
                  <div className="flex flex-col items-start gap-1">
                    {(r.packages ?? []).map((p) => <span key={p.id} className="inline-flex items-center gap-1.5 text-xs text-ink-soft">{PACKAGE_KIND[p.kind].split(' ')[0]}<PackageBadge pkg={p} className="px-2 py-0.5" /></span>)}
                    {!r.packages?.length && <span className="text-xs text-ink-faint">—</span>}
                  </div>
                </td>
                <td className="px-5 py-3.5 text-right text-xs text-ink-faint">{relTime(r.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <ul className="divide-y divide-sand-200 md:hidden">
          {rows.map((r) => (
            <li key={r.id}>
              <Link href={`/superviseur/dossiers/${r.id}`} className="block px-4 py-4">
                <div className="flex items-center justify-between gap-2"><FileStatusBadge status={r.status} /><span className="text-xs text-ink-faint">{relTime(r.updated_at)}</span></div>
                <div className="mt-1.5 font-display text-lg text-forest-900">{r.client_name || 'Client sans nom'}</div>
                <div className="text-[13px] text-ink-soft">{r.reference} · {cleanName(r.agent_name)} · {r.locality || r.commune_name || '—'}</div>
              </Link>
            </li>
          ))}
        </ul>
        {rows.length === 0 && <p className="px-5 py-12 text-center text-sm text-ink-soft">Aucun dossier ne correspond. Modifiez les filtres ou la recherche.</p>}
      </div>
    </main>
  );
}
