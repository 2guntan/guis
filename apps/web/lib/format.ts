const dateFmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Africa/Dakar' });
const dateTimeFmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Dakar' });
const numFmt = new Intl.NumberFormat('fr-FR');

export function fmtDate(v?: string | null) {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d.getTime()) ? '—' : dateFmt.format(d);
}
export function fmtDateTime(v?: string | null) {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d.getTime()) ? '—' : dateTimeFmt.format(d);
}
export function fmtXof(v?: number | string | null) {
  if (v === null || v === undefined || v === '') return '—';
  return `${numFmt.format(Number(v))} FCFA`;
}
export function fmtNum(v?: number | string | null, digits = 2) {
  if (v === null || v === undefined || v === '') return '—';
  return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: digits }).format(Number(v));
}
export function fmtHa(v?: number | string | null) {
  if (v === null || v === undefined || v === '') return '—';
  return `${fmtNum(v, 2)} ha`;
}
export function relTime(v?: string | null) {
  if (!v) return '—';
  const diff = (Date.now() - new Date(v).getTime()) / 1000;
  if (diff < 60) return 'à l’instant';
  if (diff < 3600) return `il y a ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `il y a ${Math.floor(diff / 3600)} h`;
  if (diff < 86400 * 7) return `il y a ${Math.floor(diff / 86400)} j`;
  return fmtDate(v);
}
/** Nom d'agent sans le suffixe « (agent démo) ». */
export function cleanName(v?: string | null) {
  return (v ?? '').replace(/\s*\([^)]*démo\)\s*$/i, '').trim() || '—';
}
