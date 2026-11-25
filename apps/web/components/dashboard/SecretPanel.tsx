'use client';

import { KeyRound, X } from 'lucide-react';
import { fmtPhone } from '@/lib/format';

export type Issued = { name: string; phone: string; role: string; secret: string; title: string };

/** Secret affiché une seule fois après une création ou une réinitialisation (ADR-0003). */
export function SecretPanel({ issued, onClose }: { issued: Issued; onClose: () => void }) {
  const code = issued.role === 'agent';
  return (
    <section role="status" aria-label="Secret à transmettre" className="flex items-start gap-4 rounded-md border border-[#E0A100] bg-alert-bg px-5 py-4">
      <KeyRound className="mt-1 h-5 w-5 shrink-0 text-alert-text" />
      <div className="min-w-0 flex-1">
        <div className="text-[14px] font-semibold">{issued.title}</div>
        <div className="mt-1 text-[14px]">
          {issued.name} · <span className="tabular">{fmtPhone(issued.phone)}</span>
        </div>
        <div className="mt-2 text-[14px]">
          {code ? 'Code' : 'Mot de passe'} :{' '}
          <strong data-secret className="tabular rounded bg-white px-2 py-0.5 text-[20px] tracking-[0.15em]">
            {issued.secret}
          </strong>
        </div>
        <p className="mt-2 text-[13px] text-board-muted">
          Affiché une seule fois : notez-le maintenant et transmettez-le à la personne. Il ne pourra plus être relu.
        </p>
      </div>
      <button type="button" onClick={onClose} aria-label="Fermer" className="rounded p-1 hover:bg-white/60">
        <X className="h-4 w-4" />
      </button>
    </section>
  );
}

/** Appel JSON de l'API depuis le tableau de bord (cookie de session) ; lève le message d'erreur en français. */
export async function callApi<T = unknown>(method: string, url: string, payload?: unknown): Promise<T> {
  const res = await fetch(url, {
    method,
    headers: payload === undefined ? undefined : { 'content-type': 'application/json' },
    body: payload === undefined ? undefined : JSON.stringify(payload),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `Erreur ${res.status}`);
  return data as T;
}
