import { ndviFill } from '@/lib/design';
import { fmtDM } from '@/lib/format';

// « Le champ à chaque passage du satellite » (docs/design/web/w4) : le contour coloré selon le NDVI mesuré à chaque
// image ; image nuageuse : contour pointillé gris. Ce n'est pas l'image satellite elle-même, seulement sa mesure.
export function SatellitePasses({ geometry, series }: { geometry: unknown; series: { date: string; ndvi: number | null }[] }) {
  const g = geometry as { type: string; coordinates: number[][][] } | null;
  if (!g || g.type !== 'Polygon' || series.length === 0) return null;
  const ring = g.coordinates[0];
  const lat0 = ring.reduce((a, [, y]) => a + y, 0) / ring.length;
  const k = Math.cos((lat0 * Math.PI) / 180);
  const xs = ring.map(([x]) => x * k);
  const ys = ring.map(([, y]) => y);
  const [minX, maxX, minY, maxY] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  const s = 60 / Math.max(maxX - minX, maxY - minY, 1e-9);
  const ox = (100 - (maxX - minX) * s) / 2;
  const oy = (70 - (maxY - minY) * s) / 2;
  const d = ring.map((_, i) => `${i ? 'L' : 'M'}${(ox + (xs[i] - minX) * s).toFixed(1)},${(oy + (maxY - ys[i]) * s).toFixed(1)}`).join(' ') + 'Z';
  const shown = series.slice(-6);
  return (
    <ol className="grid grid-cols-6 gap-3">
      {shown.map((p, i) => {
        const fill = ndviFill(p.ndvi);
        const last = i === shown.length - 1;
        return (
          <li key={p.date}>
            <svg viewBox="0 0 100 70" className={`w-full rounded-md ${last ? 'ring-2 ring-[#C8892B]' : ''}`} style={{ background: fill ? '#CFC8B4' : '#E4E5E0' }} role="img" aria-label={`${fmtDM(p.date)} ${p.ndvi === null ? 'nuages' : `NDVI ${p.ndvi.toFixed(2)}`}`}>
              <path d={d} fill={fill ?? 'none'} stroke={fill ? '#FFFFFF' : '#7C857E'} strokeWidth="1.5" strokeDasharray={fill ? undefined : '3 3'} />
            </svg>
            <div className={`mt-1.5 text-[13px] ${p.ndvi === null ? 'text-board-help' : last ? 'font-semibold' : ''}`}>
              {fmtDM(p.date)}, {p.ndvi === null ? 'nuages' : p.ndvi.toFixed(2).replace('.', ',')}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
