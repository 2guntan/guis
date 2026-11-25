'use client';

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Tag } from '@/components/StatusBadge';
import { callApi, SecretPanel, type Issued } from '@/components/dashboard/SecretPanel';
import { fmtDateTime, fmtPhone, relTime } from '@/lib/format';
import type { Account } from '@/lib/users';

type Role = Account['role'];
type Event = { at: string; action: string; detail: string | null; actor: string | null; target: string | null };

const ROLES: { value: Role; label: string }[] = [
  { value: 'agent', label: 'Agent' },
  { value: 'coordinator', label: 'Coordinateur' },
  { value: 'admin', label: 'Admin' },
];
const roleLabel = (r: string) => ROLES.find((x) => x.value === r)?.label ?? r;
const ACTIONS: Record<string, string> = {
  create: 'a créé',
  update: 'a modifié',
  role: 'a changé le profil de',
  reset: 'a réinitialisé le secret de',
  deactivate: 'a désactivé',
  reactivate: 'a réactivé',
  delete: 'a supprimé',
};

type Draft = { id?: string; name: string; phone: string; role: Role };
const EMPTY: Draft = { name: '', phone: '', role: 'agent' };

export function UsersManager({ me, users, events }: { me: string; users: Account[]; events: Event[] }) {
  const router = useRouter();
  const [role, setRole] = useState<'' | Role>('');
  const [state, setState] = useState<'' | 'actif' | 'inactif'>('');
  const [draft, setDraft] = useState<Draft | null>(null);
  const [issued, setIssued] = useState<Issued | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const shown = useMemo(
    () => users.filter((u) => (!role || u.role === role) && (!state || (state === 'actif') === u.active)),
    [users, role, state],
  );

  async function run<T>(fn: () => Promise<T>) {
    setBusy(true);
    setError(null);
    try {
      return await fn();
    } catch (e) {
      setError((e as Error).message);
      return null;
    } finally {
      setBusy(false);
      router.refresh();
    }
  }

  async function save() {
    if (!draft) return;
    const ok = await run(async () => {
      if (draft.id) {
        await callApi('PATCH', `/api/users/${draft.id}`, { name: draft.name, phone: draft.phone, role: draft.role });
      } else {
        const r = await callApi<{ name: string; phone: string; role: string; secret: string }>('POST', '/api/users', draft);
        setIssued({ ...r, title: 'Compte créé' });
      }
      return true;
    });
    if (ok) setDraft(null);
  }

  async function reset(u: Account) {
    const what = u.role === 'agent' ? 'le code' : 'le mot de passe';
    if (!confirm(`Réinitialiser ${what} de ${u.name} ? Ses sessions en cours seront fermées.`)) return;
    await run(async () => {
      const r = await callApi<{ name: string; phone: string; role: string; secret: string }>('POST', `/api/users/${u.id}/secret`);
      setIssued({ ...r, title: u.role === 'agent' ? 'Nouveau code' : 'Nouveau mot de passe' });
    });
  }

  async function setActive(u: Account, active: boolean) {
    if (!active && !confirm(`Désactiver ${u.name} ? Il ne pourra plus se connecter et ses communes lui seront retirées.`)) return;
    await run(() => callApi('PUT', `/api/users/${u.id}/activation`, { active }));
  }

  async function remove(u: Account) {
    if (!confirm(`Supprimer définitivement le compte de ${u.name} ?`)) return;
    await run(() => callApi('DELETE', `/api/users/${u.id}`));
  }

  return (
    <div className="space-y-5">
      {issued && <SecretPanel issued={issued} onClose={() => setIssued(null)} />}
      {error && (
        <p role="alert" className="rounded-md bg-alert-bg px-4 py-3 text-[14px]">
          {error}
        </p>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <select aria-label="Profil" className="input-b" value={role} onChange={(e) => setRole(e.target.value as '' | Role)}>
          <option value="">Tous les profils</option>
          {ROLES.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
        <select aria-label="État" className="input-b" value={state} onChange={(e) => setState(e.target.value as '' | 'actif' | 'inactif')}>
          <option value="">Actifs et désactivés</option>
          <option value="actif">Actifs</option>
          <option value="inactif">Désactivés</option>
        </select>
        <div className="ml-auto">
          <button type="button" className="btn-b" onClick={() => setDraft({ ...EMPTY })}>
            Nouveau compte
          </button>
        </div>
      </div>

      {draft && (
        <form
          className="card-b flex flex-wrap items-end gap-3 rounded-md p-4"
          onSubmit={(e) => {
            e.preventDefault();
            void save();
          }}
        >
          <label className="flex flex-col gap-1 text-[13px] text-board-help">
            Nom
            <input className="input-b w-56" required value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1 text-[13px] text-board-help">
            Téléphone
            <input className="input-b w-44" required inputMode="tel" placeholder="77 123 45 67" value={draft.phone} onChange={(e) => setDraft({ ...draft, phone: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1 text-[13px] text-board-help">
            Profil
            <select className="input-b" value={draft.role} disabled={draft.id === me} onChange={(e) => setDraft({ ...draft, role: e.target.value as Role })}>
              {ROLES.map((r) => (
                <option key={r.value} value={r.value}>
                  {r.label}
                </option>
              ))}
            </select>
          </label>
          <button className="btn-b" disabled={busy}>
            {draft.id ? 'Enregistrer' : 'Créer le compte'}
          </button>
          <button type="button" className="btn-b-ghost" onClick={() => setDraft(null)}>
            Annuler
          </button>
          {!draft.id && (
            <p className="w-full text-[13px] text-board-muted">
              Un agent reçoit un code de 4 chiffres ; un admin ou un coordinateur, un mot de passe. Il s’affichera une seule fois.
            </p>
          )}
        </form>
      )}

      <div className="card-b overflow-x-auto rounded-md">
        <table className="w-full text-left text-[14px]">
          <thead className="border-b border-line bg-chalk text-[13px] text-board-help">
            <tr>
              <th className="px-4 py-2 font-medium">Nom</th>
              <th className="px-4 py-2 font-medium">Téléphone</th>
              <th className="px-4 py-2 font-medium">Profil</th>
              <th className="px-4 py-2 font-medium">État</th>
              <th className="px-4 py-2 font-medium">Dernière synchronisation</th>
              <th className="px-4 py-2 font-medium">Dernière réinitialisation</th>
              <th className="px-4 py-2" />
            </tr>
          </thead>
          <tbody>
            {shown.map((u) => (
              <tr key={u.id} className="border-b border-line last:border-0" data-user={u.phone}>
                <td className="px-4 py-2 font-semibold">
                  {u.name}
                  {u.id === me && <span className="ml-2 text-[12px] font-normal text-board-help">(vous)</span>}
                  {u.role === 'agent' && u.communes.length > 0 && <div className="text-[12px] font-normal text-board-help">{u.communes.join(', ')}</div>}
                </td>
                <td className="tabular px-4 py-2">{fmtPhone(u.phone)}</td>
                <td className="px-4 py-2">{roleLabel(u.role)}</td>
                <td className="px-4 py-2">{u.active ? <Tag tone="neutral">Actif</Tag> : <Tag tone="ochre">Désactivé</Tag>}</td>
                <td className="px-4 py-2 text-board-muted">{u.role === 'coordinator' ? '—' : relTime(u.last_sync_at)}</td>
                <td className="px-4 py-2 text-board-muted">
                  {u.last_reset_at ? `${fmtDateTime(u.last_reset_at)}${u.last_reset_by ? ` · ${u.last_reset_by}` : ''}` : '—'}
                </td>
                <td className="whitespace-nowrap px-4 py-2 text-right">
                  <button type="button" className="btn-b-ghost h-8 px-3" onClick={() => setDraft({ id: u.id, name: u.name, phone: u.phone.replace(/^221/, ''), role: u.role })}>
                    Modifier
                  </button>{' '}
                  <button type="button" className="btn-b-ghost h-8 px-3" disabled={busy} onClick={() => void reset(u)}>
                    {u.role === 'agent' ? 'Réinitialiser le code' : 'Réinitialiser le mot de passe'}
                  </button>{' '}
                  {u.id !== me &&
                    (u.active ? (
                      <button type="button" className="btn-b-ghost h-8 px-3" disabled={busy} onClick={() => void setActive(u, false)}>
                        Désactiver
                      </button>
                    ) : (
                      <button type="button" className="btn-b-ghost h-8 px-3" disabled={busy} onClick={() => void setActive(u, true)}>
                        Réactiver
                      </button>
                    ))}{' '}
                  {u.id !== me && u.deletable && (
                    <button type="button" className="btn-b-ghost h-8 px-3 text-clay-text" disabled={busy} onClick={() => void remove(u)}>
                      Supprimer
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {shown.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-board-help">
                  Aucun compte.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <section>
        <h2 className="mb-2 text-[15px] font-semibold">Journal des comptes</h2>
        {events.length === 0 ? (
          <p className="text-[14px] text-board-help">Aucune action enregistrée.</p>
        ) : (
          <ul className="space-y-1 text-[14px]">
            {events.map((e, i) => (
              <li key={i}>
                <span className="text-board-help">{fmtDateTime(e.at)}</span> · {e.actor ?? 'Compte supprimé'} {ACTIONS[e.action] ?? e.action} {e.target ?? 'un compte supprimé'}
                {e.action === 'role' && e.detail ? ` (${e.detail.replace(/\b(admin|coordinator|agent)\b/g, (r) => roleLabel(r))})` : ''}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
