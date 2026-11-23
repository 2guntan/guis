// Même règle que lib/phone.ts (les scripts tournent sans compilation TypeScript).
export function normalizePhone(raw) {
  let d = String(raw ?? '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.length === 9) d = '221' + d;
  return d;
}
