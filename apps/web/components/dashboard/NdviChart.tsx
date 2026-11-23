'use client';

import { Area, AreaChart, CartesianGrid, ReferenceArea, ReferenceDot, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

const short = new Intl.DateTimeFormat('fr-FR', { month: 'short', year: '2-digit' });

export default function NdviChart({ series, bands = [], flooding = [] }: {
  series: { date: string; ndvi: number; cloud_pct?: number }[];
  /** Saisons d'hivernage à surligner (fond vert si cultivée). */
  bands?: { start: string; end: string; cultivated: boolean }[];
  /** Dates de mise en eau détectées au radar. */
  flooding?: string[];
}) {
  const data = series.filter((p) => typeof p.ndvi === 'number').map((p) => ({ ...p, t: new Date(p.date).getTime() }));
  const min = data.length ? data[0].t : 0;
  const max = data.length ? data[data.length - 1].t : 0;
  const clamp = (t: number) => Math.min(max, Math.max(min, t));
  return (
    <div className="h-40 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 6, right: 6, bottom: 0, left: -24 }}>
          <defs>
            <linearGradient id="ndvi" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#2F6B4F" stopOpacity={0.35} />
              <stop offset="100%" stopColor="#2F6B4F" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          {bands.map((b) => (
            <ReferenceArea key={b.start} x1={clamp(new Date(b.start).getTime())} x2={clamp(new Date(b.end).getTime())} y1={0} y2={1}
              fill={b.cultivated ? '#2F6B4F' : '#CFC4AA'} fillOpacity={b.cultivated ? 0.08 : 0.18} stroke="none" ifOverflow="hidden" />
          ))}
          <CartesianGrid stroke="#E3DBC7" vertical={false} />
          <XAxis dataKey="t" type="number" domain={['dataMin', 'dataMax']} scale="time" tickFormatter={(v) => short.format(new Date(v))} tick={{ fontSize: 11, fill: '#7C857E' }} tickLine={false} axisLine={false} minTickGap={24} />
          <YAxis domain={[0, 1]} ticks={[0, 0.25, 0.5, 0.75, 1]} tick={{ fontSize: 11, fill: '#7C857E' }} tickLine={false} axisLine={false} />
          <Tooltip
            labelFormatter={(v) => new Date(v as number).toLocaleDateString('fr-FR')}
            formatter={(v) => [Number(v).toFixed(2), 'NDVI']}
            contentStyle={{ borderRadius: 10, border: '1px solid #E3DBC7', fontSize: 12 }}
          />
          <Area type="monotone" dataKey="ndvi" stroke="#1E4D3A" strokeWidth={1.8} fill="url(#ndvi)" dot={{ r: 1.5, fill: '#1E4D3A' }} />
          {flooding.map((d) => {
            const t = new Date(d).getTime();
            return t >= min && t <= max ? <ReferenceDot key={d} x={t} y={0.06} r={4} fill="#3E6E8E" stroke="#fff" strokeWidth={1.5} /> : null;
          })}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
