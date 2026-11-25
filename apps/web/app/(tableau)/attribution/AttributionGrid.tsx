'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Tag } from '@/components/StatusBadge';
import { callApi, SecretPanel, type Issued } from '@/components/dashboard/SecretPanel';
import { fmtNum, fmtPhone, relTime } from '@/lib/format';
import type { Grid } from '@/lib/attribution';

export function AttributionGrid({ grid }: { grid: Grid }) {
  const router = useRouter();
  const [cells, setCells] = useState(() => new Set(grid.communes.flatMap((c) => c.agents.map((a) => `${c.name}|${a}`))));
  const [issued, setIssued] = useState<Issued | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function toggle(commune: string, agentId: string, assigned: boolean) {
    const key = `${commune}|${agentId}`;
    setBusy(key);
    setError(null);
    try {
      await callApi('PUT', '/api/attribution', { commune, user_id: agentId, assigned });
      setCells((prev) => {
        const next = new Set(prev);
        if (assigned) next.add(key);
        else next.delete(key);
        return next;
      });
      router.refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  }

  async function resetCode(a: Grid['agents'][number]) {
    if (!confirm(`Réinitialiser le code de ${a.name} ? Son téléphone lui redemandera de se connecter ; ses saisies non envoyées sont gardées.`)) return;
    setError(null);
    try {
      const r = await callApi<{ name: string; phone: string; role: string; secret: string }>('POST', `/api/attribution/agents/${a.id}/code`);
      setIssued({ ...r, title: 'Nouveau code' });
    } catch (e) {
      setError((e as Error).message);
    }
  }

  const agentsOf = (commune: string) => grid.agents.filter((a) => cells.has(`${commune}|${a.id}`)).length;

  return (
    <div className="space-y-5">
      {issued && <SecretPanel issued={issued} onClose={() => setIssued(null)} />}
      {error && (
        <p role="alert" className="rounded-md bg-alert-bg px-4 py-3 text-[14px]">
          {error}
        </p>
      )}
      <p className="text-[14px] text-board-muted">
        Cochez une case pour confier une commune à un agent. Le changement arrive sur son téléphone à sa prochaine synchronisation. Avant de retirer une
        commune, vérifiez que l’agent a bien envoyé ses saisies.
      </p>
      {grid.agents.length === 0 ? (
        <p className="py-10 text-center text-board-help">Aucun agent actif. L’admin crée les comptes agents sur la page « Utilisateurs ».</p>
      ) : (
        <div className="card-b overflow-x-auto rounded-md">
          <table className="w-full text-left text-[14px]">
            <thead className="border-b border-line bg-chalk align-bottom text-[13px] text-board-help">
              <tr>
                <th className="px-4 py-2 font-medium">Commune</th>
                <th className="px-4 py-2 text-right font-medium">Producteurs</th>
                {grid.agents.map((a) => (
                  <th key={a.id} className="min-w-[150px] px-3 py-2 text-center font-medium" data-agent={a.phone}>
                    <div className="font-semibold text-board-text">{a.name}</div>
                    <div className="tabular">{fmtPhone(a.phone)}</div>
                    <div>Synchro : {relTime(a.last_sync_at)}</div>
                    <button type="button" className="btn-b-ghost mt-1 h-7 px-2 text-[12px]" onClick={() => void resetCode(a)}>
                      Réinitialiser le code
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {grid.communes.map((c) => (
                <tr key={c.name} className="border-b border-line last:border-0" data-commune={c.name}>
                  <td className="px-4 py-2 font-semibold">
                    {c.name}
                    {agentsOf(c.name) === 0 && (
                      <span className="ml-2">
                        <Tag tone="alert">Aucun agent</Tag>
                      </span>
                    )}
                  </td>
                  <td className="tabular px-4 py-2 text-right">{fmtNum(c.producers, 0)}</td>
                  {grid.agents.map((a) => {
                    const key = `${c.name}|${a.id}`;
                    const on = cells.has(key);
                    return (
                      <td key={a.id} className="px-3 py-2 text-center">
                        <input
                          type="checkbox"
                          className="h-5 w-5 accent-forest"
                          aria-label={`${c.name} : ${a.name}`}
                          checked={on}
                          disabled={busy === key}
                          onChange={(e) => void toggle(c.name, a.id, e.target.checked)}
                        />
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
