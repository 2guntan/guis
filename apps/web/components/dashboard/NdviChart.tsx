'use client';

// Repris de Fieldproof (components/superviseur/NdviChart.tsx) : saisons et radar retirés. Direction B
// (docs/design/web/w4-fiche-champ.png) : axe en jours depuis le semis, plage attendue de la pomme de terre,
// repères « Semis » et « Aujourd'hui », dernier point en jaune quand le NDVI baisse.
import { Area, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { expectedNdvi } from '@/lib/expected';

const DAY = 86_400_000;
const BAND = 0.08;

export default function NdviChart({
  series,
  sownOn,
  today,
  dropAlert,
}: {
  series: { date: string; ndvi: number | null }[];
  sownOn: string | null;
  today: string;
  dropAlert?: boolean;
}) {
  const t0 = new Date(`${sownOn ?? series[0]?.date ?? today}T00:00:00Z`).getTime();
  const day = (d: string) => Math.round((new Date(`${d}T00:00:00Z`).getTime() - t0) / DAY);
  const points = series.filter((p) => p.ndvi !== null).map((p) => ({ j: day(p.date), ndvi: p.ndvi as number, date: p.date }));
  const now = day(today);
  const end = Math.max(110, now + 5, points.at(-1)?.j ?? 0);
  const band = sownOn
    ? Array.from({ length: Math.floor(end / 5) + 1 }, (_, i) => i * 5).map((j) => {
        const e = expectedNdvi(j);
        return { j, band: [Math.max(0, e - BAND), e + BAND] as [number, number] };
      })
    : [];
  const data = [...band, ...points].sort((a, b) => a.j - b.j);
  const lastIdx = data.findLastIndex((d) => 'ndvi' in d);
  const ticks = [-15, 0, 30, 60, 90, 110].filter((t) => t <= end);
  return (
    <div className="h-[230px] w-full">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: -20 }}>
          <CartesianGrid stroke="#E5EAE2" vertical={false} />
          <XAxis
            dataKey="j"
            type="number"
            domain={[-15, end]}
            ticks={ticks}
            tickFormatter={(v) => (sownOn ? (v === 0 ? 'J0' : `J${v > 0 ? '+' : '−'}${Math.abs(v)}`) : `${v} j`)}
            tick={{ fontSize: 12, fill: '#4F5F55' }}
            tickLine={false}
            axisLine={{ stroke: '#D3DAD0' }}
          />
          <YAxis domain={[0, 0.9]} ticks={[0, 0.3, 0.6, 0.9]} tickFormatter={(v) => String(v).replace('.', ',')} tick={{ fontSize: 12, fill: '#4F5F55' }} tickLine={false} axisLine={false} />
          <Tooltip
            labelFormatter={(v) => (sownOn ? `J${Number(v) >= 0 ? '+' : '−'}${Math.abs(Number(v))}` : `${v} j`)}
            formatter={(v, name) =>
              name === 'band'
                ? [`${(v as number[]).map((x) => x.toFixed(2).replace('.', ',')).join(' à ')}`, 'Plage attendue']
                : [Number(v).toFixed(2).replace('.', ','), 'NDVI mesuré']
            }
            contentStyle={{ borderRadius: 8, border: '1px solid #D3DAD0', fontSize: 12 }}
          />
          <Area dataKey="band" type="monotone" stroke="none" fill="#A9C47F" fillOpacity={0.35} connectNulls isAnimationActive={false} />
          {sownOn && <ReferenceLine x={0} stroke="#163A2C" strokeDasharray="3 3" label={{ value: 'Semis', position: 'insideTopRight', fontSize: 12, fill: '#163A2C', fontWeight: 600 }} />}
          <ReferenceLine x={now} stroke="#D3DAD0" label={{ value: 'Aujourd’hui', position: 'insideTopRight', fontSize: 12, fill: '#4F5F55' }} />
          <Line
            dataKey="ndvi"
            type="linear"
            stroke="#163A2C"
            strokeWidth={1.8}
            connectNulls
            isAnimationActive={false}
            dot={(props: { cx?: number; cy?: number; index?: number; value?: unknown }) => {
              const { cx, cy, index, value } = props;
              if (value == null || cx == null || cy == null) return <g key={`d${index}`} />;
              const last = index === lastIdx;
              return <circle key={`d${index}`} cx={cx} cy={cy} r={last ? 4 : 2.5} fill={last && dropAlert ? '#E0A100' : '#163A2C'} />;
            }}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
