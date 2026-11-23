/**
 * Numéro de téléphone normalisé : chiffres seulement, avec l'indicatif du Sénégal (221)
 * ajouté aux numéros locaux à 9 chiffres. « 77 123 45 67 », « +221771234567 » et
 * « 00221 77 123 45 67 » donnent tous « 221771234567 ».
 */
export function normalizePhone(raw: string | null | undefined): string {
  let d = (raw ?? '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.length === 9) d = '221' + d;
  return d;
}
