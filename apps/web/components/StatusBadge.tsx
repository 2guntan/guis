import { cn } from '@/lib/utils';
import { STATUS_FILL, STATUS_SHORT } from '@/lib/design';
import type { FieldStatus } from '@/lib/labels';

// Repris de Fieldproof (components/StatusBadge.tsx) puis refait pour la direction B : carré de couleur et mot.

/** Statut d'un champ : petit carré de la rampe NDVI (pointillé sans contour) et libellé. */
export function StatusMark({ status, className }: { status: FieldStatus; className?: string }) {
  const fill = STATUS_FILL[status];
  return (
    <span className={cn('inline-flex items-center gap-2 text-[14px]', className)}>
      <span className="h-3 w-3 shrink-0 rounded-[3px]" style={fill ? { background: fill } : { border: '1.5px dashed #163A2C' }} />
      {STATUS_SHORT[status]}
    </span>
  );
}

/** Pastille encadrée (en-tête de la fiche). */
export function StatusPill({ status }: { status: FieldStatus }) {
  return (
    <span className="inline-flex items-center rounded-md border border-line bg-white px-2.5 py-1 text-[14px] font-semibold">
      <StatusMark status={status} />
    </span>
  );
}

const TAGS = {
  alert: 'border border-[#E0A100] bg-alert-bg text-alert-text',
  neutral: 'bg-[#E5EAE2] text-board-text',
  ochre: 'bg-[#F5E9D3] text-[#6E4E00]',
  sky: 'bg-[#DCE7EE] text-[#24526D]',
};

/** Étiquette : alerte (jaune), suivi indicatif (gris), aucun champ relevé (ocre), consentement à recueillir (bleu). */
export function Tag({ tone, children }: { tone: keyof typeof TAGS; children: React.ReactNode }) {
  return <span className={cn('inline-flex items-center rounded-[4px] px-2 py-0.5 text-[13px] font-semibold', TAGS[tone])}>{children}</span>;
}
