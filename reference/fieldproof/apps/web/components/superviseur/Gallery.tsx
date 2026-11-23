'use client';

import { useState } from 'react';
import { ChevronLeft, ChevronRight, FileText, History } from 'lucide-react';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { fmtDateTime } from '@/lib/format';

export type GalleryItem = { id: string; label: string; url: string | null; mime: string; captured_at: string | null; lat: number | null; lng: number | null; versions: number };

export function Gallery({ items }: { items: GalleryItem[] }) {
  const [open, setOpen] = useState<number | null>(null);
  if (!items.length) return <p className="text-sm text-ink-soft">Aucune pièce déposée.</p>;
  const cur = open === null ? null : items[open];
  return (
    <>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-4">
        {items.map((it, i) => (
          <button key={it.id} onClick={() => setOpen(i)} className="group text-left">
            <div className="aspect-[4/3] overflow-hidden rounded-xl bg-sand-100 ring-1 ring-sand-200 transition group-hover:ring-forest-300">
              {it.mime.startsWith('image/') && it.url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={it.url} alt={it.label} className="h-full w-full object-cover" loading="lazy" />
              ) : (
                <span className="flex h-full items-center justify-center text-ink-soft"><FileText className="h-7 w-7" /></span>
              )}
            </div>
            <div className="mt-1.5 truncate text-[13px] font-medium text-ink">{it.label}</div>
            <div className="flex items-center gap-1.5 text-xs text-ink-faint">
              {fmtDateTime(it.captured_at)}
              {it.versions > 0 && <span className="inline-flex items-center gap-0.5"><History className="h-3 w-3" />v{it.versions + 1}</span>}
            </div>
          </button>
        ))}
      </div>
      <Dialog open={cur !== null} onOpenChange={(o) => !o && setOpen(null)}>
        <DialogContent wide>
          {cur && (
            <>
              <DialogTitle>{cur.label}</DialogTitle>
              <div className="relative mt-4">
                {cur.mime.startsWith('image/') && cur.url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={cur.url} alt={cur.label} className="max-h-[68dvh] w-full rounded-xl bg-sand-100 object-contain" />
                ) : cur.url ? (
                  <iframe src={cur.url} className="h-[68dvh] w-full rounded-xl" title={cur.label} />
                ) : <p className="text-sm text-ink-soft">Fichier indisponible.</p>}
                {items.length > 1 && <>
                  <button onClick={() => setOpen((open! - 1 + items.length) % items.length)} className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-surface/90 p-2 shadow-card" aria-label="Précédente"><ChevronLeft className="h-5 w-5" /></button>
                  <button onClick={() => setOpen((open! + 1) % items.length)} className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-surface/90 p-2 shadow-card" aria-label="Suivante"><ChevronRight className="h-5 w-5" /></button>
                </>}
              </div>
              <p className="mt-3 text-xs text-ink-faint">
                Prise le {fmtDateTime(cur.captured_at)}{cur.lat ? ` · ${cur.lat.toFixed(5)}, ${cur.lng?.toFixed(5)}` : ' · position non relevée'}
                {cur.versions > 0 ? ` · ${cur.versions} version${cur.versions > 1 ? 's' : ''} antérieure${cur.versions > 1 ? 's' : ''} archivée${cur.versions > 1 ? 's' : ''}` : ''}
              </p>
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
