'use client';

// Repris de Fieldproof (components/superviseur/NdviChart.tsx) : saisons et radar retirés ; courbe attendue de la
// pomme de terre (pointillés) et date de semis ajoutées.
import { Area, ComposedChart, CartesianGrid, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { expectedNdvi } from '@/lib/expected';

const short = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short' });
const DAY = 86_400_000;

export default function NdviChart({ series, sownOn, today }: { series: { date: string; ndvi: number | null }[]; sownOn: string | null; today: string }) {
  const sown = sownOn ? new Date(`${sownOn}T00:00:00Z`).getTime() : null;
  const points = series.filter((p) => typeof p.ndvi === 'number').map((p) => ({ t: new Date(`${p.date}T00:00:00Z`).getTime(), ndvi: p.ndvi }));
  const end = Math.max(new Date(`${today}T00:00:00Z`).getTime(), points.at(-1)?.t ?? 0, sown ? sown + 110 * DAY : 0);
  const start = sown ? sown - 15 * DAY : (points[0]?.t ?? end - 120 * DAY);
  const expected = sown ? Array.from({ length: Math.floor((end - start) / (5 * DAY)) + 1 }, (_, i) => start + i * 5 * DAY).map((t) => ({ t, attendu: expectedNdvi((t - sown) / DAY) })) : [];
  const data = [...points, ...expected].sort((a, b) => a.t - b.t);
  return (
    <div className="h-64 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={data} margin={{ top: 6, right: 12, bottom: 0, left: -18 }}>
          <defs>
            <linearGradient id="ndvi" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#2F6B4F" stopOpacity={0.35} />
              <stop offset="100%" stopColor="#2F6B4F" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="#E3DBC7" vertical={false} />
          <XAxis dataKey="t" type="number" domain={[start, end]} scale="time" tickFormatter={(v) => short.format(new Date(v))} tick={{ fontSize: 11, fill: '#7C857E' }} tickLine={false} axisLine={false} minTickGap={24} />
          <YAxis domain={[0, 1]} ticks={[0, 0.25, 0.5, 0.75, 1]} tick={{ fontSize: 11, fill: '#7C857E' }} tickLine={false} axisLine={false} />
          <Tooltip
            labelFormatter={(v) => new Date(v as number).toLocaleDateString('fr-FR')}
            formatter={(v, name) => [Number(v).toFixed(2), name === 'attendu' ? 'Attendu' : 'NDVI']}
            contentStyle={{ borderRadius: 10, border: '1px solid #E3DBC7', fontSize: 12 }}
          />
          {sown && <ReferenceLine x={sown} stroke="#C08A2B" strokeDasharray="3 3" label={{ value: 'Semis', position: 'insideTopLeft', fontSize: 11, fill: '#8A5F14' }} />}
          <Line dataKey="attendu" type="monotone" stroke="#C08A2B" strokeDasharray="5 4" strokeWidth={1.5} dot={false} connectNulls isAnimationActive={false} />
          <Area dataKey="ndvi" type="monotone" stroke="#1E4D3A" strokeWidth={1.8} fill="url(#ndvi)" dot={{ r: 2.5, fill: '#1E4D3A' }} connectNulls isAnimationActive={false} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
