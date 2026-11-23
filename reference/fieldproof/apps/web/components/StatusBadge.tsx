import { cn } from '@/lib/utils';
import { FILE_STATUS, type FileStatus, packageState } from '@/lib/labels';

const fileTone: Record<FileStatus, string> = {
  draft: 'bg-sand-100 text-ink-soft ring-sand-300',
  submitted: 'bg-sky-50 text-sky-700 ring-sky-500/30',
  returned: 'bg-ochre-50 text-ochre-700 ring-ochre-500/40',
  sent: 'bg-forest-50 text-forest-700 ring-forest-500/30',
  closed: 'bg-sand-100 text-ink-faint ring-sand-300',
};

const dotTone: Record<FileStatus, string> = {
  draft: 'bg-ink-faint',
  submitted: 'bg-sky-500',
  returned: 'bg-ochre-500',
  sent: 'bg-forest-500',
  closed: 'bg-ink-faint',
};

export function FileStatusBadge({ status, className }: { status: FileStatus; className?: string }) {
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset', fileTone[status], className)}>
      <span className={cn('h-1.5 w-1.5 rounded-full', dotTone[status])} />
      {FILE_STATUS[status] ?? status}
    </span>
  );
}

const pkgTone: Record<string, string> = {
  pending: 'bg-sand-100 text-ink-soft ring-sand-300',
  ready: 'bg-sky-50 text-sky-700 ring-sky-500/30',
  received: 'bg-ochre-50 text-ochre-700 ring-ochre-500/40',
  integrated: 'bg-forest-50 text-forest-700 ring-forest-500/30',
  rejected: 'bg-clay-50 text-clay-700 ring-clay-500/30',
  failed: 'bg-clay-50 text-clay-700 ring-clay-500/30',
};

export function PackageBadge({ pkg, className }: { pkg: { generation_status: string; lender_status?: string | null }; className?: string }) {
  const s = packageState(pkg);
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset', pkgTone[s.key], className)}>
      {s.key === 'pending' && <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ochre-500" />}
      {s.label}
    </span>
  );
}

export function Tone({ tone, children, className }: { tone: 'forest' | 'ochre' | 'clay' | 'neutral' | 'sky'; children: React.ReactNode; className?: string }) {
  const map = {
    forest: 'bg-forest-50 text-forest-700 ring-forest-500/30',
    ochre: 'bg-ochre-50 text-ochre-700 ring-ochre-500/40',
    clay: 'bg-clay-50 text-clay-700 ring-clay-500/30',
    sky: 'bg-sky-50 text-sky-700 ring-sky-500/30',
    neutral: 'bg-sand-100 text-ink-soft ring-sand-300',
  };
  return <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset', map[tone], className)}>{children}</span>;
}
