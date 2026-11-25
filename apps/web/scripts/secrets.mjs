// Même règle que lib/secrets.ts (les scripts tournent sans compilation TypeScript) : code de 4
// chiffres pour un agent, jamais évident (ADR-0003) ; mot de passe de 10 caractères sinon.
import { randomInt } from 'node:crypto';

const LETTERS = 'abcdefghjkmnpqrstuvwxyz23456789';

export function isObviousCode(code, phone = '') {
  if (!/^\d{4}$/.test(code)) return true;
  const d = [...code].map(Number);
  if (d.every((x) => x === d[0])) return true;
  const step = d[1] - d[0];
  if ((step === 1 || step === -1) && d.every((x, i) => i === 0 || x - d[i - 1] === step)) return true;
  const digits = String(phone).replace(/\D/g, '');
  return digits.length >= 4 && digits.endsWith(code);
}

export function generateCode(phone = '') {
  for (;;) {
    const code = String(randomInt(10000)).padStart(4, '0');
    if (!isObviousCode(code, phone)) return code;
  }
}

export function generatePassword() {
  return Array.from({ length: 10 }, () => LETTERS[randomInt(LETTERS.length)]).join('');
}
