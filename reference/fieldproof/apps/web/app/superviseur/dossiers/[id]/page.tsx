import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, CircleCheck, FileText, MapPin, Phone, TriangleAlert } from 'lucide-react';
import { requireRole } from '@/lib/session';
import { FileStatusBadge, PackageBadge } from '@/components/StatusBadge';
import { ParcelsMap } from '@/components/map/ParcelsMap';
import { Gallery, type GalleryItem } from '@/components/superviseur/Gallery';
import { RetroCard, type Retro } from '@/components/superviseur/RetroCard';
import { SupervisorActions } from '@/components/superviseur/SupervisorActions';
import { SendingsPanel, type SendingView } from '@/components/superviseur/SendingsPanel';
import { ConsentsPanel, type ConsentView } from '@/components/superviseur/ConsentsPanel';
import { cleanName, fmtDate, fmtDateTime, fmtHa, fmtNum, fmtXof } from '@/lib/format';
import { DOC_KIND, FILE_STATUS, ID_DOC, MARITAL, OCCUPATION, PACKAGE_KIND, REPAYMENT, type FileStatus, type PackageKind } from '@/lib/labels';
import type { Completeness, LenderConfig } from '@/lib/draft';

export const metadata: Metadata = { title: 'Dossier client' };
export const dynamic = 'force-dynamic';

/* eslint-disable @typescript-eslint/no-explicit-any */
export default async function FileDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const s = await requireRole('supervisor');
  const db = s.supabase;

  const [{ data: file }, { data: ov }] = await Promise.all([
    db.schema('dossier').from('client_files').select('*').eq('id', id).maybeSingle(),
    db.schema('dossier').from('file_overview').select('agent_name, branch_name, lender_name, region_name, commune_name, team_name').eq('id', id).maybeSingle(),
  ]);
  if (!file) notFound();
  const f = file as any;

  const [client, farm, parcels, documents, consents, completeness, history, packages, sendings, config, units, routes] = await Promise.all([
    db.schema('identity').from('clients').select('*').eq('id', f.client_id).maybeSingle(),
    f.farm_id ? db.schema('identity').from('farms').select('*').eq('id', f.farm_id).maybeSingle() : Promise.resolve({ data: null }),
    f.farm_id ? db.schema('identity').from('parcels').select('id, name, geometry, gps_area_ha, gps_perimeter_m, geometry_invalid_reason, geometry_precision_m, geometry_source, geometry_captured_at, crop, declared_area_ha, occupation_type').eq('farm_id', f.farm_id).is('archived_at', null).order('created_at') : Promise.resolve({ data: [] }),
    db.schema('dossier').from('documents').select('*').eq('file_id', id).order('created_at'),
    db.schema('dossier').from('consents').select('*').eq('file_id', id).order('created_at', { ascending: false }),
    db.schema('dossier').rpc('completeness', { p_file: id }),
    db.schema('dossier').from('file_status_history').select('*').eq('file_id', id).order('recorded_at', { ascending: false }),
    db.schema('dossier').from('packages').select('*').eq('file_id', id).order('created_at'),
    db.schema('dossier').from('sendings').select('id, branch_unit_id, to_email, cc_email, token_hint, expires_at, revoked_at, mail_status, mail_error, mail_sent_at, created_at').eq('file_id', id).order('created_at', { ascending: false }),
    db.schema('dossier').from('lender_configs').select('config').eq('organization_id', f.lender_organization_id).maybeSingle(),
    db.schema('core').from('org_units').select('id, name, code, kind').eq('organization_id', f.lender_organization_id),
    db.schema('dossier').from('branch_routes').select('org_unit_id, email, active'),
  ]);

  const parcelRows = (parcels.data ?? []) as any[];
  const docs = (documents.data ?? []) as any[];
  const pkgs = (packages.data ?? []) as any[];
  const sendRows = (sendings.data ?? []) as any[];
  const sendingIds = sendRows.map((x) => x.id);
  const pkgIds = pkgs.map((p) => p.id);
  const actorIds = Array.from(new Set(((history.data ?? []) as any[]).map((h) => h.actor_id).filter(Boolean)));

  const [retro, logs, sp, pdocs, actors, village] = await Promise.all([
    parcelRows.length ? db.schema('watch').from('latest_retro').select('*').in('parcel_id', parcelRows.map((p) => p.id)) : Promise.resolve({ data: [] }),
    sendingIds.length ? db.schema('dossier').from('link_access_log').select('id, sending_id, action, detail, ip, user_agent, at').in('sending_id', sendingIds).order('at', { ascending: false }).limit(200) : Promise.resolve({ data: [] }),
    sendingIds.length ? db.schema('dossier').from('sending_packages').select('sending_id, package_id').in('sending_id', sendingIds) : Promise.resolve({ data: [] }),
    pkgIds.length ? db.schema('dossier').from('package_documents').select('id, package_id, kind, label, storage_path, mime_type').in('package_id', pkgIds) : Promise.resolve({ data: [] }),
    actorIds.length ? db.schema('core').from('profiles').select('id, full_name').in('id', actorIds) : Promise.resolve({ data: [] }),
    client.data?.village_id ? db.schema('core').from('geo_villages').select('name').eq('id', client.data.village_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);

  // URL signées (1 h) : pièces et documents des paquets, lus avec la session du superviseur (RLS Storage)
  const paths = [...docs.map((d) => d.storage_path), ...((pdocs.data ?? []) as any[]).map((d) => d.storage_path)];
  const signed: Record<string, string> = {};
  if (paths.length) {
    const { data } = await db.storage.from('documents').createSignedUrls(paths, 3600);
    for (const d of data ?? []) if (d.path && d.signedUrl) signed[d.path] = d.signedUrl;
  }

  const c = (client.data ?? {}) as any;
  const fa = farm.data as any;
  const comp = (completeness.data ?? { complete: false, missing: [] }) as Completeness;
  const cfg = (config.data?.config ?? { required_documents: [], complementary_fields: [] }) as LenderConfig;
  const status = f.status as FileStatus;
  const routeMap = new Map(((routes.data ?? []) as any[]).map((r) => [r.org_unit_id, r]));
  const branches = ((units.data ?? []) as any[]).filter((u) => u.kind === 'branch' && routeMap.get(u.id)?.active).map((u) => ({ id: u.id, name: u.name, email: routeMap.get(u.id)!.email as string }));
  const actorName = new Map(((actors.data ?? []) as any[]).map((a) => [a.id, cleanName(a.full_name)]));
  const retroByParcel = new Map(((retro.data ?? []) as Retro[]).map((r) => [r.parcel_id, r]));

  const activeDocs = docs.filter((d) => d.superseded_by === null && !d.kind.startsWith('consent_'));
  const gallery: GalleryItem[] = activeDocs.map((d) => ({
    id: d.id, label: DOC_KIND[d.kind] ?? cfg.required_documents.find((r) => r.kind === d.kind)?.label ?? d.kind,
    url: signed[d.storage_path] ?? null, mime: d.mime_type, captured_at: d.captured_at ?? d.created_at, lat: d.lat, lng: d.lng,
    versions: docs.filter((x) => x.kind === d.kind && x.superseded_by !== null && x.superseded_by !== x.id && !['parcel_photo', 'other'].includes(x.kind)).length,
  }));
  const docById = new Map(docs.map((d) => [d.id, d]));
  const consentViews: ConsentView[] = ((consents.data ?? []) as any[]).map((k) => ({
    id: k.id, purpose: k.purpose, granted: k.granted, method: k.method, notice_version: k.notice_version, language: k.language,
    lat: k.lat, lng: k.lng, collected_at: k.collected_at, withdrawn_at: k.withdrawn_at, withdrawal_reason: k.withdrawal_reason,
    signature_url: k.signature_document_id ? signed[docById.get(k.signature_document_id)?.storage_path] ?? null : null,
    photo_url: k.photo_document_id ? signed[docById.get(k.photo_document_id)?.storage_path] ?? null : null,
  }));
  const pkgsBySending = new Map<string, any[]>();
  for (const row of (sp.data ?? []) as any[]) pkgsBySending.set(row.sending_id, [...(pkgsBySending.get(row.sending_id) ?? []), pkgs.find((p) => p.id === row.package_id)].filter(Boolean));
  const sendingViews: SendingView[] = sendRows.map((x) => ({
    ...x, branch_name: (units.data ?? []).find((u: any) => u.id === x.branch_unit_id)?.name ?? '—',
    packages: (pkgsBySending.get(x.id) ?? []).map((p) => ({ id: p.id, kind: p.kind, generation_status: p.generation_status, lender_status: p.lender_status })),
    log: ((logs.data ?? []) as any[]).filter((l) => l.sending_id === x.id),
  }));
  const extraFields = (cfg.complementary_fields ?? []).filter((x) => f.extra_fields?.[x.key] !== undefined && f.extra_fields?.[x.key] !== '');
  const sentKinds = pkgs.filter((p) => p.lender_status !== 'rejected').map((p) => p.kind as PackageKind);
  const title = (v?: string | null) => (v ? v.charAt(0) + v.slice(1).toLowerCase() : '');

  return (
    <main className="mx-auto max-w-7xl px-4 pb-16 pt-6 sm:px-6">
      <Link href="/superviseur/dossiers" className="inline-flex items-center gap-1.5 text-sm text-ink-soft hover:text-ink"><ArrowLeft className="h-4 w-4" />Dossiers</Link>

      <header className="mt-4 flex flex-wrap items-start justify-between gap-6">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <FileStatusBadge status={status} />
            <span className="text-sm tabular text-ink-faint">{f.reference}</span>
          </div>
          <h1 className="mt-2 text-[48px] leading-[1.05] tracking-tight">{c.display_name || 'Client sans nom'}</h1>
          <p className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-ink-soft">
            <span className="inline-flex items-center gap-1.5"><MapPin className="h-4 w-4" />{[c.locality, title(ov?.commune_name), title(ov?.region_name)].filter(Boolean).join(', ') || '—'}</span>
            {c.phone && <span className="inline-flex items-center gap-1.5"><Phone className="h-4 w-4" />{c.phone}</span>}
            <span>Agent : {cleanName(ov?.agent_name)}</span>
            <span>Prêteur : {ov?.lender_name ?? '—'}</span>
          </p>
        </div>
      </header>

      {status === 'returned' && f.return_reason && (
        <p className="mt-5 flex items-start gap-2 rounded-xl border border-ochre-400/50 bg-ochre-50 px-4 py-3 text-sm text-ochre-700">
          <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0" /><span><b>Renvoyé à l’agent :</b> {f.return_reason}</span>
        </p>
      )}

      <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="min-w-0 space-y-8">
          {/* Parcelles et analyse rétroactive */}
          <section className="panel overflow-hidden">
            <div className="h-[340px] bg-forest-900">
              <ParcelsMap className="h-[340px] w-full" point={f.collected_lat ? { lat: f.collected_lat, lng: f.collected_lng } : null}
                parcels={parcelRows.map((p) => ({ id: p.id, name: p.name, geometry: p.geometry, invalid: Boolean(p.geometry_invalid_reason), label: `${p.name} · ${fmtHa(p.gps_area_ha)}` }))} />
            </div>
            <div className="p-5">
              <div className="flex flex-wrap items-baseline justify-between gap-3">
                <h2 className="text-2xl">Exploitation et parcelles</h2>
                <span className="text-sm text-ink-soft">{fa?.name ?? 'Exploitation non renseignée'}</span>
              </div>
              {fa && (
                <dl className="mt-4 grid gap-x-6 gap-y-3 text-sm sm:grid-cols-3">
                  <Field k="Activité" v={fa.main_activity} />
                  <Field k="Cultures" v={(fa.crops ?? []).join(', ')} />
                  <Field k="Expérience" v={fa.experience_years ? `${fa.experience_years} ans` : null} />
                  <Field k="Surface déclarée" v={fa.total_area_ha ? fmtHa(fa.total_area_ha) : null} />
                  <Field k="Travailleurs" v={fa.workers_count} />
                  <Field k="Source d’eau" v={fa.water_source} />
                  <Field k="Chiffre d’affaires annuel" v={fa.annual_revenue_xof ? fmtXof(fa.annual_revenue_xof) : null} />
                </dl>
              )}
              <div className="mt-6 space-y-4">
                {parcelRows.length === 0 && <p className="text-sm text-ink-soft">Aucune parcelle tracée.</p>}
                {parcelRows.map((p) => (
                  <div key={p.id} className="rounded-xl border border-sand-200 p-4">
                    <div className="flex flex-wrap items-center justify-between gap-3">
                      <div>
                        <div className="font-medium">{p.name}</div>
                        <div className="text-[13px] text-ink-soft">
                          GPS {fmtHa(p.gps_area_ha)} · déclarée {fmtHa(p.declared_area_ha)} · périmètre {fmtNum(p.gps_perimeter_m, 0)} m
                          {p.geometry_precision_m ? ` · ± ${p.geometry_precision_m} m` : ''} · {p.geometry_source === 'agent_walk' ? 'contour marché' : 'sommets placés'}
                        </div>
                        <div className="text-[13px] text-ink-soft">{[p.crop, OCCUPATION[p.occupation_type]].filter(Boolean).join(' · ')}</div>
                      </div>
                      {p.geometry_invalid_reason ? <span className="rounded-full bg-clay-50 px-2.5 py-1 text-xs text-clay-700">Contour invalide : {p.geometry_invalid_reason}</span> : null}
                    </div>
                    <RetroCard retro={retroByParcel.get(p.id) ?? null} hasGeometry={Boolean(p.geometry) && !p.geometry_invalid_reason} />
                  </div>
                ))}
              </div>
            </div>
          </section>

          <section className="panel p-5">
            <h2 className="text-2xl">Identité et adresse</h2>
            <dl className="mt-4 grid gap-x-6 gap-y-3 text-sm sm:grid-cols-3">
              <Field k="Sexe" v={c.gender === 'F' ? 'Femme' : c.gender === 'M' ? 'Homme' : null} />
              <Field k="Naissance" v={c.birth_date ? `${fmtDate(c.birth_date)}${c.birth_place ? `, ${c.birth_place}` : ''}` : null} />
              <Field k="Nationalité" v={c.nationality} />
              <Field k="Situation" v={MARITAL[c.marital_status]} />
              <Field k="Profession" v={c.profession} />
              <Field k="Pièce" v={c.id_document_number ? `${ID_DOC[c.id_document_type] ?? ''} n° ${c.id_document_number}` : null} />
              <Field k="Validité de la pièce" v={c.id_document_expires_on ? `${fmtDate(c.id_document_issued_on)} → ${fmtDate(c.id_document_expires_on)}` : null} />
              <Field k="Téléphones" v={[c.phone, c.phone_alt].filter(Boolean).join(' / ')} />
              <Field k="Village" v={title(village.data?.name)} />
              <Field k="Adresse" v={c.address} wide />
            </dl>
            <h3 className="mt-7 text-xl">Besoin</h3>
            <dl className="mt-3 grid gap-x-6 gap-y-3 text-sm sm:grid-cols-3">
              <Field k="Paquets demandés" v={[f.wants_account_opening && 'Ouverture de compte', f.wants_credit && 'Demande de crédit'].filter(Boolean).join(' + ')} />
              <Field k="N° de compte prêteur" v={f.lender_account_number} />
              {f.wants_credit && <>
                <Field k="Montant" v={fmtXof(f.credit_amount_xof)} />
                <Field k="Durée" v={f.credit_duration_months ? `${f.credit_duration_months} mois` : null} />
                <Field k="Remboursement" v={REPAYMENT[f.repayment_frequency]} />
                <Field k="Objet" v={f.credit_purpose} wide />
              </>}
            </dl>
            {extraFields.length > 0 && <>
              <h3 className="mt-7 text-xl">Champs complémentaires du prêteur</h3>
              <dl className="mt-3 grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                {extraFields.map((x) => <Field key={x.key} k={x.label} v={String(f.extra_fields[x.key])} />)}
              </dl>
            </>}
          </section>

          <section className="panel p-5">
            <h2 className="text-2xl">Pièces</h2>
            <p className="mt-1 text-sm text-ink-soft">Dernière version de chaque pièce. Touchez une vignette pour l’agrandir.</p>
            <div className="mt-4"><Gallery items={gallery} /></div>
          </section>

          <section className="panel p-5">
            <h2 className="text-2xl">Consentements</h2>
            <div className="mt-4"><ConsentsPanel fileId={id} consents={consentViews} /></div>
          </section>
        </div>

        <aside className="space-y-6 lg:sticky lg:top-20 lg:self-start">
          <SupervisorActions
            fileId={id}
            status={status}
            reference={f.reference}
            clientName={c.display_name ?? ''}
            branchId={f.branch_unit_id}
            branchName={ov?.branch_name ?? null}
            branchManual={f.branch_set_manually}
            branches={branches}
            complete={comp.complete}
            wantsAccount={f.wants_account_opening}
            wantsCredit={f.wants_credit}
            accountNumber={f.lender_account_number}
            sentKinds={sentKinds}
            appUrl={process.env.NEXT_PUBLIC_APP_URL ?? ''}
          />

          <section className="panel p-5">
            <h3 className="eyebrow font-sans">Complétude</h3>
            {comp.complete ? (
              <p className="mt-2 flex items-center gap-2 text-sm text-forest-700"><CircleCheck className="h-4 w-4" />Dossier complet</p>
            ) : (
              <ul className="mt-2 space-y-1.5 text-sm text-ochre-700">
                {comp.missing.map((m) => <li key={m.code} className="flex gap-2"><TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />{m.label}</li>)}
              </ul>
            )}
          </section>

          {pkgs.length > 0 && (
            <section className="panel p-5">
              <h3 className="eyebrow font-sans">Paquets</h3>
              <ul className="mt-3 space-y-4">
                {pkgs.slice().reverse().map((p) => {
                  const pd = ((pdocs.data ?? []) as any[]).filter((d) => d.package_id === p.id);
                  return (
                    <li key={p.id} className="text-sm">
                      <div className="flex items-center justify-between gap-2"><span className="font-medium">{PACKAGE_KIND[p.kind as PackageKind]}</span><PackageBadge pkg={p} /></div>
                      <div className="mt-0.5 text-xs text-ink-faint">Créé le {fmtDateTime(p.created_at)}{p.lender_declared_at ? ` · retour le ${fmtDateTime(p.lender_declared_at)}` : ''}</div>
                      {p.lender_reference && <div className="mt-1">Référence prêteur : <span className="tabular font-medium">{p.lender_reference}</span></div>}
                      {p.rejection_reason && <div className="mt-1 text-clay-700">Motif du rejet : {p.rejection_reason}</div>}
                      {p.generation_error && <div className="mt-1 text-clay-700">Erreur de génération : {p.generation_error}</div>}
                      {pd.length > 0 && (
                        <details className="mt-2">
                        <summary className="cursor-pointer text-[13px] text-ink-soft">{pd.length} document{pd.length > 1 ? 's' : ''} générés</summary>
                        <ul className="mt-2 space-y-1">
                          {pd.map((d) => (
                            <li key={d.id}><a href={signed[d.storage_path]} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 text-forest-700 hover:underline"><FileText className="h-3.5 w-3.5" />{d.label}</a></li>
                          ))}
                        </ul>
                        </details>
                      )}
                      {p.generation_status === 'pending' && <div className="mt-1 text-xs text-ink-faint">Documents en préparation par le service de génération.</div>}
                    </li>
                  );
                })}
              </ul>
            </section>
          )}

          <SendingsPanel sendings={sendingViews} />

          <section className="panel p-5">
            <h3 className="eyebrow font-sans">Historique des statuts</h3>
            <ol className="mt-3 space-y-3 border-l border-sand-300 pl-4">
              {((history.data ?? []) as any[]).map((h) => (
                <li key={h.id} className="relative text-sm">
                  <span className="absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-surface bg-forest-500" />
                  <div><span className="font-medium">{FILE_STATUS[h.to_status as FileStatus]}</span> <span className="text-ink-faint">· {actorName.get(h.actor_id) ?? '—'}</span></div>
                  <div className="text-xs text-ink-faint">{fmtDateTime(h.recorded_at)}{h.command_at && Math.abs(new Date(h.command_at).getTime() - new Date(h.recorded_at).getTime()) > 120000 ? ` (commande du ${fmtDateTime(h.command_at)})` : ''}</div>
                  {h.reason && <div className="mt-1 rounded-lg bg-ochre-50 px-2.5 py-1.5 text-ochre-700">{h.reason}</div>}
                </li>
              ))}
            </ol>
          </section>
        </aside>
      </div>
    </main>
  );
}

function Field({ k, v, wide }: { k: string; v: unknown; wide?: boolean }) {
  const text = v === null || v === undefined || v === '' ? '—' : String(v);
  return (
    <div className={wide ? 'sm:col-span-3' : undefined}>
      <dt className="text-xs text-ink-faint">{k}</dt>
      <dd className="mt-0.5 text-ink">{text}</dd>
    </div>
  );
}
