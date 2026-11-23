import type { Metadata } from 'next';
import Link from 'next/link';
import { ArrowUpRight, Clock, Inbox, Link2, MailWarning } from 'lucide-react';
import { requireRole } from '@/lib/session';
import { FileStatusBadge, PackageBadge, Tone } from '@/components/StatusBadge';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { cleanName, fmtXof, relTime } from '@/lib/format';
import { FILE_STATUS, MAIL_STATUS, PACKAGE_KIND, type FileStatus, type MailStatus, type PackageKind } from '@/lib/labels';
import { cn } from '@/lib/utils';

export const metadata: Metadata = { title: 'Tableau de bord' };
export const dynamic = 'force-dynamic';

type Overview = {
  id: string; reference: string; status: FileStatus; client_name: string | null; agent_name: string | null; region_name: string | null;
  commune_name: string | null; locality: string | null; submitted_at: string | null; sent_at: string | null; updated_at: string;
  credit_amount_xof: number | null; parcel_count: number; total_gps_area_ha: number | null; client_id: string;
};
type Sending = { id: string; file_id: string; created_at: string; mail_status: MailStatus; expires_at: string; revoked_at: string | null; to_email: string };
type Pkg = { id: string; file_id: string; kind: PackageKind; generation_status: string; lender_status: string | null; lender_reference: string | null; rejection_reason: string | null; lender_declared_at: string };

const PIPE: FileStatus[] = ['draft', 'submitted', 'returned', 'sent'];
/** Un dossier soumis qui attend plus longtemps que ce délai remonte dans « À traiter maintenant ». */
const STALE_HOURS = 48;

type Alert = { key: string; tone: 'clay' | 'ochre' | 'sky'; title: string; text: string; href: string; action: string };
const ALERT_TONE = {
  clay: { dot: 'bg-clay-500', text: 'text-clay-700' },
  ochre: { dot: 'bg-ochre-500', text: 'text-ochre-700' },
  sky: { dot: 'bg-sky-500', text: 'text-sky-700' },
};

export default async function Dashboard() {
  const s = await requireRole('supervisor');
  const db = s.supabase;
  const nowIso = new Date().toISOString();
  const [files, sendings, returns, parcels, failedPkgs, unsentMails] = await Promise.all([
    db.schema('dossier').from('file_overview')
      .select('id, reference, status, client_name, agent_name, region_name, commune_name, locality, submitted_at, sent_at, updated_at, credit_amount_xof, parcel_count, total_gps_area_ha, client_id')
      .order('updated_at', { ascending: false }),
    db.schema('dossier').from('sendings').select('id, file_id, created_at, mail_status, expires_at, revoked_at, to_email').order('created_at', { ascending: false }).limit(6),
    db.schema('dossier').from('packages').select('id, file_id, kind, generation_status, lender_status, lender_reference, rejection_reason, lender_declared_at')
      .not('lender_status', 'is', null).order('lender_declared_at', { ascending: false }).limit(6),
    db.schema('identity').from('parcels').select('id, name, geometry, geometry_invalid_reason').is('archived_at', null).not('geometry', 'is', null).limit(300),
    db.schema('dossier').from('packages').select('id, file_id, kind').eq('generation_status', 'failed').limit(20),
    db.schema('dossier').from('sendings').select('id, file_id, created_at').eq('mail_status', 'logged_only').is('revoked_at', null).gt('expires_at', nowIso).limit(20),
  ]);
  const rows = (files.data ?? []) as Overview[];
  const byId = new Map(rows.map((r) => [r.id, r]));
  const count = (st: FileStatus) => rows.filter((r) => r.status === st).length;
  const toVerify = rows.filter((r) => r.status === 'submitted').sort((a, b) => (a.submitted_at ?? '').localeCompare(b.submitted_at ?? ''));
  const staleLimit = Date.now() - STALE_HOURS * 3600 * 1000;
  const stale = toVerify.filter((r) => r.submitted_at && new Date(r.submitted_at).getTime() < staleLimit);
  const label = (id: string) => [byId.get(id)?.reference, byId.get(id)?.client_name].filter(Boolean).join(' · ') || 'Dossier';
  const alerts: Alert[] = [
    ...((failedPkgs.data ?? []) as { id: string; file_id: string; kind: PackageKind }[]).map((p) => ({
      key: `pkg-${p.id}`, tone: 'clay' as const, title: 'Génération en échec', href: `/superviseur/dossiers/${p.file_id}`, action: 'Relancer la génération',
      text: `${label(p.file_id)} — ${PACKAGE_KIND[p.kind]} : le prêteur ne peut ni télécharger ni déclarer.`,
    })),
    ...((unsentMails.data ?? []) as { id: string; file_id: string; created_at: string }[]).map((x) => ({
      key: `mail-${x.id}`, tone: 'ochre' as const, title: 'Mail non expédié', href: `/superviseur/dossiers/${x.file_id}`, action: 'Ouvrir le dossier',
      text: `${label(x.file_id)} — le lien n’est que journalisé : transmettez-le à la caisse.`,
    })),
    ...stale.map((r) => ({
      key: `stale-${r.id}`, tone: 'sky' as const, title: `Soumis ${relTime(r.submitted_at)}`, href: `/superviseur/dossiers/${r.id}`, action: 'Vérifier',
      text: `${r.reference} · ${r.client_name || 'Client sans nom'} — en attente de vérification depuis plus de ${STALE_HOURS} h.`,
    })),
  ];
  const totalHa = rows.reduce((acc, r) => acc + Number(r.total_gps_area_ha ?? 0), 0);
  const today = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Africa/Dakar' }).format(new Date());

  return (
    <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm text-ink-soft">{today.charAt(0).toUpperCase() + today.slice(1)}</p>
          <h1 className="text-[44px] leading-[1.1] tracking-tight">Tableau de bord</h1>
        </div>
        <Link href="/superviseur/dossiers?statut=submitted" className="inline-flex h-11 items-center gap-2 rounded-xl bg-forest-800 px-4 text-[15px] font-medium text-paper hover:bg-forest-900">
          <Inbox className="h-4 w-4" />{toVerify.length} dossier{toVerify.length > 1 ? 's' : ''} à vérifier
        </Link>
      </div>

      {alerts.length > 0 && (
        <section className="panel mt-7 overflow-hidden" aria-labelledby="alertes">
          <h2 id="alertes" className="eyebrow border-b border-sand-200 px-5 py-3.5 font-sans">À traiter maintenant · {alerts.length} alerte{alerts.length > 1 ? 's' : ''}</h2>
          <ul className="divide-y divide-sand-200">
            {alerts.map((a) => (
              <li key={a.key}>
                <Link href={a.href} className="group grid gap-x-4 gap-y-1 px-5 py-3.5 transition hover:bg-sand-100/60 md:grid-cols-[14px_220px_1fr_auto] md:items-center">
                  <span className={cn('hidden h-2 w-2 rounded-full md:block', ALERT_TONE[a.tone].dot)} />
                  <span className={cn('text-sm font-semibold', ALERT_TONE[a.tone].text)}>{a.title}</span>
                  <span className="text-sm text-ink">{a.text}</span>
                  <span className="text-sm font-medium text-forest-700 group-hover:underline">{a.action} →</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* Chaîne des statuts : du brouillon à l'envoi */}
      <section className="mt-9 grid grid-cols-2 gap-y-6 sm:grid-cols-4">
        {PIPE.map((st, i) => (
          <Link key={st} href={`/superviseur/dossiers?statut=${st}`}
            className={cn('group px-5 transition first:pl-0 sm:border-l sm:border-sand-300 sm:first:border-l-0', i % 2 === 1 && 'border-l border-sand-300', i === 2 && 'pl-0 sm:pl-5')}>
            <div className={cn('eyebrow flex items-center gap-1.5', st === 'submitted' && count(st) > 0 ? 'text-sky-700' : 'text-ink-faint')}>
              {FILE_STATUS[st]}<ArrowUpRight className="h-3.5 w-3.5 opacity-0 transition group-hover:opacity-100" />
            </div>
            <div className={cn('mt-1 font-display text-[56px] leading-[1.05] tabular', st === 'submitted' && count(st) > 0 ? 'text-sky-700' : 'text-forest-900')}>{count(st)}</div>
            <div className="mt-0.5 text-[13px] text-ink-soft">
              {st === 'draft' && 'en cours de collecte'}
              {st === 'submitted' && 'en attente de vérification'}
              {st === 'returned' && 'à corriger par l’agent'}
              {st === 'sent' && 'chez le prêteur'}
            </div>
          </Link>
        ))}
      </section>

      <div className="mt-8 grid gap-8 lg:grid-cols-[1.35fr_1fr]">
        <div className="space-y-8">
          <section>
            <h2 className="text-2xl">À vérifier</h2>
            <p className="mt-1 text-sm text-ink-soft">Les plus anciennes soumissions en premier.</p>
            <div className="panel mt-4 divide-y divide-sand-200">
              {toVerify.length === 0 && <p className="px-5 py-10 text-center text-sm text-ink-soft">Aucun dossier en attente. Les nouvelles soumissions des agents apparaîtront ici.</p>}
              {toVerify.slice(0, 8).map((r) => (
                <Link key={r.id} href={`/superviseur/dossiers/${r.id}`} className="flex items-center gap-4 px-5 py-4 transition hover:bg-sand-100/60">
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-display text-[19px] text-forest-900">{r.client_name || 'Client sans nom'}</div>
                    <div className="mt-0.5 truncate text-[13px] text-ink-soft">
                      {r.reference} · {cleanName(r.agent_name)} · {r.locality || r.commune_name || r.region_name || '—'}
                    </div>
                  </div>
                  <div className="hidden text-right text-sm sm:block">
                    <div className="tabular">{r.credit_amount_xof ? fmtXof(r.credit_amount_xof) : 'Compte seul'}</div>
                    <div className="text-xs text-ink-faint">{r.parcel_count} parcelle{r.parcel_count > 1 ? 's' : ''}</div>
                  </div>
                  <span className={cn('inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-1 text-xs', stale.includes(r) ? 'bg-ochre-50 text-ochre-700' : 'bg-sand-100 text-ink-soft')}><Clock className="h-3 w-3" />{relTime(r.submitted_at)}</span>
                </Link>
              ))}
            </div>
          </section>

          <section className="panel overflow-hidden">
            <div className="flex items-baseline justify-between gap-4 px-5 pt-5">
              <div>
                <h2 className="text-2xl">Parcelles tracées</h2>
                <p className="mt-1 text-sm text-ink-soft">{(parcels.data ?? []).length} parcelles · {totalHa.toLocaleString('fr-FR', { maximumFractionDigits: 1 })} ha relevés au GPS</p>
              </div>
            </div>
            <div className="mt-4 h-80">
              <ParcelsMap className="h-80 w-full" parcels={(parcels.data ?? []).map((p: { id: string; name: string; geometry: unknown; geometry_invalid_reason: string | null }) => ({ id: p.id, name: p.name, geometry: p.geometry, invalid: Boolean(p.geometry_invalid_reason) }))} />
            </div>
          </section>
        </div>

        <div className="space-y-8">
          <section>
            <h2 className="text-2xl">Retours du prêteur</h2>
            <div className="panel mt-4 divide-y divide-sand-200">
              {(returns.data ?? []).length === 0 && <p className="px-5 py-8 text-center text-sm text-ink-soft">Aucun retour déclaré pour l’instant.</p>}
              {((returns.data ?? []) as Pkg[]).map((p) => {
                const f = byId.get(p.file_id);
                return (
                  <Link key={p.id} href={`/superviseur/dossiers/${p.file_id}`} className="block px-5 py-4 hover:bg-sand-100/60">
                    <div className="flex items-center justify-between gap-3">
                      <span className="truncate font-medium">{f?.client_name ?? 'Dossier'}</span>
                      <PackageBadge pkg={p} />
                    </div>
                    <div className="mt-1 text-[13px] text-ink-soft">
                      {PACKAGE_KIND[p.kind]}
                      {p.lender_reference && <> · réf. <span className="tabular font-medium text-ink">{p.lender_reference}</span></>}
                      {p.rejection_reason && <> · {p.rejection_reason}</>}
                    </div>
                    <div className="mt-0.5 text-xs text-ink-faint">{relTime(p.lender_declared_at)}</div>
                  </Link>
                );
              })}
            </div>
          </section>

          <section>
            <h2 className="text-2xl">Envois récents</h2>
            <div className="panel mt-4 divide-y divide-sand-200">
              {(sendings.data ?? []).length === 0 && <p className="px-5 py-8 text-center text-sm text-ink-soft">Aucun envoi. Un dossier vérifié s’envoie depuis sa fiche.</p>}
              {((sendings.data ?? []) as Sending[]).map((x) => {
                const f = byId.get(x.file_id);
                const expired = new Date(x.expires_at) < new Date();
                return (
                  <Link key={x.id} href={`/superviseur/dossiers/${x.file_id}`} className="flex items-start gap-3 px-5 py-4 hover:bg-sand-100/60">
                    <Link2 className="mt-0.5 h-4 w-4 shrink-0 text-ink-faint" />
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-medium">{f?.client_name ?? 'Dossier'} <span className="text-xs font-normal text-ink-faint">{f?.reference}</span></div>
                      <div className="truncate text-[13px] text-ink-soft">{x.to_email} · {relTime(x.created_at)}</div>
                    </div>
                    {x.revoked_at ? <Tone tone="clay">Révoqué</Tone> : expired ? <Tone tone="neutral">Expiré</Tone> : (
                      <Tone tone={x.mail_status === 'sent' ? 'forest' : x.mail_status === 'queued' ? 'neutral' : 'ochre'}>
                        {x.mail_status === 'logged_only' && <MailWarning className="h-3 w-3" />}{MAIL_STATUS[x.mail_status]}
                      </Tone>
                    )}
                  </Link>
                );
              })}
            </div>
          </section>

        </div>
      </div>
    </main>
  );
}
