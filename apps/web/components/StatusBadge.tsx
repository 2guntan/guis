import { cn } from '@/lib/utils';
import { FIELD_STATUS, STATUS_TONE, type FieldStatus } from '@/lib/labels';

// Repris de Fieldproof (components/StatusBadge.tsx) : pastilles de couleur ; statuts de dossier remplacés par
// les statuts satellite d'un champ.

const TONES = {
  forest: 'bg-forest-50 text-forest-700 ring-forest-500/30',
  ochre: 'bg-ochre-50 text-ochre-700 ring-ochre-500/40',
  clay: 'bg-clay-50 text-clay-700 ring-clay-500/30',
  sky: 'bg-sky-50 text-sky-700 ring-sky-500/30',
  neutral: 'bg-sand-100 text-ink-soft ring-sand-300',
};

export function Tone({ tone, children, className }: { tone: keyof typeof TONES; children: React.ReactNode; className?: string }) {
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset', TONES[tone], className)}>
      {children}
    </span>
  );
}

/** Couleur du champ sur la carte, par statut. */
export const STATUS_COLOR: Record<FieldStatus, string> = {
  none: '#7C857E',
  waiting: '#CFC4AA',
  bare: '#D9A23F',
  emergence: '#7FA68C',
  growth: '#2F6B4F',
  peak: '#1E4D3A',
  senescence: '#C08A2B',
};

export function FieldStatusBadge({ status, className }: { status: FieldStatus; className?: string }) {
  return (
    <Tone tone={STATUS_TONE[status]} className={className}>
      <span className="h-1.5 w-1.5 rounded-full" style={{ background: STATUS_COLOR[status] }} />
      {FIELD_STATUS[status] ?? status}
    </Tone>
  );
}
