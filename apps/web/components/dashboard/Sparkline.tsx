// Mini-courbe NDVI d'un champ (liste des champs) : trait sombre, dernier point vert ou jaune s'il baisse.
export function Sparkline({ values, alert }: { values: number[]; alert?: boolean }) {
  if (values.length === 0) return <span className="text-[13px] text-board-help">pas d’image</span>;
  const w = 104;
  const h = 24;
  // Échelle propre au champ (amplitude d'au moins 0,3) : la forme de la courbe se lit même sur 24 px.
  const lo = Math.max(0, Math.min(...values) - 0.03);
  const hi = Math.max(lo + 0.3, Math.max(...values) + 0.03);
  const y = (v: number) => h - 4 - ((v - lo) / (hi - lo)) * (h - 8);
  const pts = values.map((v, i) => [values.length === 1 ? w - 4 : 4 + (i * (w - 8)) / (values.length - 1), y(v)] as const);
  const last = pts[pts.length - 1];
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} role="img" aria-label={`NDVI ${values.map((v) => v.toFixed(2)).join(', ')}`}>
      <line x1="2" x2={w - 2} y1={h - 2} y2={h - 2} stroke="#E5EAE2" />
      <polyline points={pts.map(([x, y]) => `${x},${y}`).join(' ')} fill="none" stroke="#163A2C" strokeWidth="1.3" />
      <circle cx={last[0]} cy={last[1]} r="3" fill={alert ? '#E0A100' : '#163A2C'} />
    </svg>
  );
}
