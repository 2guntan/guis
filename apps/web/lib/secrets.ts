import 'server-only';
import { randomInt } from 'node:crypto';
import type { Role } from '@/lib/rights';

/**
 * Secrets générés par le serveur (ADR-0003) : un code de 4 chiffres pour un agent, un mot de passe
 * d'au moins 10 caractères pour l'admin et le coordinateur. Affichés une seule fois ; seule leur
 * empreinte bcrypt est gardée. Même règle que scripts/secrets.mjs (scripts sans TypeScript).
 */
const LETTERS = 'abcdefghjkmnpqrstuvwxyz23456789';

/** Code trop facile à deviner : chiffres identiques, suite (1234, 4321, 0123…), fin du téléphone. */
export function isObviousCode(code: string, phone = ''): boolean {
  if (!/^\d{4}$/.test(code)) return true;
  const d = [...code].map(Number);
  if (d.every((x) => x === d[0])) return true;
  const step = d[1] - d[0];
  if ((step === 1 || step === -1) && d.every((x, i) => i === 0 || x - d[i - 1] === step)) return true;
  const digits = phone.replace(/\D/g, '');
  return digits.length >= 4 && digits.endsWith(code);
}

export function generateCode(phone = ''): string {
  for (;;) {
    const code = String(randomInt(10000)).padStart(4, '0');
    if (!isObviousCode(code, phone)) return code;
  }
}

export function generatePassword(): string {
  return Array.from({ length: 10 }, () => LETTERS[randomInt(LETTERS.length)]).join('');
}

export const generateSecret = (role: Role, phone: string) => (role === 'agent' ? generateCode(phone) : generatePassword());
