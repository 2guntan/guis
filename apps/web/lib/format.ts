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
  return `${new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(v))} ha`;
}
/** 15/11/2026 */
export function fmtDay(v?: string | null) {
  if (!v) return '—';
  const d = new Date(v.length === 10 ? `${v}T00:00:00Z` : v);
  return isNaN(d.getTime()) ? '—' : new Intl.DateTimeFormat('fr-FR', { timeZone: v.length === 10 ? 'UTC' : 'Africa/Dakar' }).format(d);
}
/** 15/11 */
export function fmtDM(v?: string | null) {
  return fmtDay(v).slice(0, 5);
}
/** −21 %, +8 % */
export function fmtGap(measured?: number | null, declared?: number | null) {
  if (measured == null || !declared) return null;
  const g = Math.round(((measured - declared) / declared) * 100);
  return { value: g, text: `${g > 0 ? '+' : g < 0 ? '−' : ''}${Math.abs(g)} %` };
}
/** Téléphone affiché « 77 123 45 67 ». */
export function fmtPhone(v?: string | null) {
  if (!v) return '';
  let d = v.replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('221')) d = d.slice(3);
  return d.length === 9 ? `${d.slice(0, 2)} ${d.slice(2, 5)} ${d.slice(5, 7)} ${d.slice(7)}` : v;
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
