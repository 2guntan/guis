import type { Metadata } from 'next';
import { TopBar } from '@/components/dashboard/TopBar';
import { Tag } from '@/components/StatusBadge';
import { listDuplicates, type DuplicateSide } from '@/lib/duplicates';
import { requireDashboard } from '@/lib/auth';
import { fmtDay, fmtPhone } from '@/lib/format';
import { can } from '@/lib/rights';

export const metadata: Metadata = { title: 'Doublons possibles' };

const DONE: Record<string, string> = {
  distinct: 'C’est noté : ce sont deux personnes.',
  merge: 'Fusion faite : les champs et les remises ont rejoint le producteur existant.',
};

function Side({ p, title }: { p: DuplicateSide; title: string }) {
  return (
    <div className="min-w-0 flex-1 rounded-md border border-line bg-white p-4">
      <div className="text-[13px] font-semibold uppercase tracking-wide text-board-help">{title}</div>
      <div className="mt-1 text-[16px] font-semibold" style={{ fontWeight: 650 }}>
        {p.name}
      </div>
      <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[14px]">
        <dt className="text-board-help">Téléphone</dt>
        <dd className="tabular">{fmtPhone(p.phone) || '—'}</dd>
        <dt className="text-board-help">Carte</dt>
        <dd>{p.member_card ?? '—'}</dd>
        <dt className="text-board-help">Village</dt>
        <dd>{p.village ?? '—'}</dd>
        <dt className="text-board-help">Commune</dt>
        <dd>{p.commune ?? '—'}</dd>
        <dt className="text-board-help">Origine</dt>
        <dd>{p.source === 'import' ? 'Fiche de la coopérative' : `Saisi par ${p.agent_name ?? 'un agent'} le ${fmtDay(p.created_at)}`}</dd>
        <dt className="text-board-help">Relevés</dt>
        <dd>
          {p.fields} champ{p.fields > 1 ? 's' : ''}, {p.seeds} remise{p.seeds > 1 ? 's' : ''}
        </dd>
      </dl>
    </div>
  );
}

// Doublons possibles (ticket 13) : un agent a créé un producteur dont le téléphone existe déjà.
export default async function DuplicatesPage({ searchParams }: { searchParams: Promise<{ fait?: string; erreur?: string }> }) {
  const sp = await searchParams;
  const [user, list] = await Promise.all([requireDashboard(), listDuplicates()]);
  const decide = can(user, 'decide_duplicates');
  return (
    <div>
      <TopBar title="Doublons possibles" />
      <div className="mx-auto max-w-[1100px] space-y-6 px-6 py-6">
        {sp.fait && DONE[sp.fait] && <p className="rounded-md bg-[#E5EAE2] px-4 py-3 text-[14px]">{DONE[sp.fait]}</p>}
        {sp.erreur && <p className="rounded-md bg-alert-bg px-4 py-3 text-[14px]">Action impossible : la liste a peut-être changé. Réessayez.</p>}
        <p className="text-[14px] text-board-muted">
          Un agent a créé ces producteurs avec un numéro de téléphone déjà connu. Rien n’est fusionné sans la décision de l’admin.
        </p>
        {list.length === 0 && <p className="py-10 text-center text-board-help">Aucun doublon possible.</p>}
        {list.map((d) => (
          <section key={d.id} className="rounded-lg border border-line bg-chalk p-4" aria-label={`Doublon possible : ${d.name}`}>
            <div className="mb-3">
              <Tag tone="alert">Doublon possible</Tag>
            </div>
            {d.candidates.map((c) => (
              <div key={c.id} className="mb-3 flex flex-wrap items-stretch gap-3">
                <Side p={d} title="Saisi sur le terrain" />
                <Side p={c} title="Déjà enregistré" />
                {decide && (
                <form action={`/api/doublons/${d.id}`} method="post" className="flex items-center">
                  <input type="hidden" name="action" value="merge" />
                  <input type="hidden" name="into" value={c.id} />
                  <button className="btn-b">Fusionner dans celui-ci</button>
                </form>
                )}
              </div>
            ))}
            {decide && (
            <form action={`/api/doublons/${d.id}`} method="post">
              <input type="hidden" name="action" value="distinct" />
              <button className="btn-b-ghost">
                {d.candidates.length > 1 ? 'Ce sont des personnes différentes' : 'Ce sont deux personnes'}
              </button>
            </form>
            )}
          </section>
        ))}
      </div>
    </div>
  );
}
