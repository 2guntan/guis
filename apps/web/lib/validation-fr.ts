import type { z } from 'zod';

/**
 * Refus de validation lisibles par un agent de terrain : le nom de la case de la fiche
 * (« Date de semis ») au lieu du chemin technique (`sown_on`), et une phrase simple
 * au lieu du message brut de Zod (« doit correspondre au motif /^\d{4}…/ »).
 * Le message s'affiche tel quel dans l'app, sous « Refusé par le serveur ».
 */
const LABELS: Record<string, string> = {
  // Producteur
  last_name: 'Nom',
  first_name: 'Prénom',
  phone: 'Téléphone',
  member_card: 'Carte de membre',
  sex: 'Femme / Homme',
  village: 'Village',
  photo_id: 'Photo',
  consent_at: 'Consentement',
  seeds: 'Semences reçues',
  variety: 'Variété',
  quantity_kg: 'Quantité (kg)',
  received_on: 'Date de réception',
  deleted_seed_ids: 'Semences retirées',
  // Champ
  producer_id: 'Producteur',
  contour: 'Point du contour',
  lat: 'Latitude',
  lng: 'Longitude',
  accuracy_m: 'Précision GPS',
  captured_at: 'Heure du point',
  area_declared_ha: 'Surface déclarée',
  sown_on: 'Date de semis',
  irrigation: 'Irrigation',
  water_source: 'Source d’eau',
  base_edited_at: 'Date de modification',
  // Tableau de bord
  name: 'Nom',
  role: 'Profil',
  password: 'Mot de passe',
  commune: 'Commune',
  user_id: 'Agent',
  assigned: 'Attribution',
  active: 'Activation',
};

/** « Point du contour n° 4, Latitude » pour `contour.3.lat`. */
function where(path: PropertyKey[]): string {
  const parts: string[] = [];
  for (const p of path) {
    if (typeof p === 'number') {
      if (parts.length) parts[parts.length - 1] += ` n° ${p + 1}`;
    } else {
      parts.push(LABELS[String(p)] ?? String(p));
    }
  }
  return parts.join(', ');
}

const fmt = (n: unknown) => (typeof n === 'number' ? n.toLocaleString('fr-FR') : String(n));

function what(issue: z.core.$ZodIssue): string {
  switch (issue.code) {
    case 'too_small':
      if (issue.origin === 'string') return Number(issue.minimum) <= 1 ? 'à remplir' : `trop court (${fmt(issue.minimum)} caractères au moins)`;
      if (issue.origin === 'number') return issue.inclusive ? `doit valoir au moins ${fmt(issue.minimum)}` : `doit être plus grand que ${fmt(issue.minimum)}`;
      if (issue.origin === 'array') return `au moins ${fmt(issue.minimum)} attendu(s)`;
      break;
    case 'too_big':
      if (issue.origin === 'string') return `trop long (${fmt(issue.maximum)} caractères au plus)`;
      if (issue.origin === 'number') return `ne doit pas dépasser ${fmt(issue.maximum)}`;
      if (issue.origin === 'array') return `trop nombreux (${fmt(issue.maximum)} au plus)`;
      break;
    case 'invalid_format':
      if (issue.format === 'regex' && String((issue as { pattern?: unknown }).pattern).includes('\\d{4}-\\d{2}-\\d{2}')) return 'date invalide (jour, mois, année attendus)';
      if (issue.format === 'datetime') return 'date et heure invalides';
      if (issue.format === 'uuid' || issue.format === 'guid') return 'identifiant invalide';
      return 'format invalide';
    case 'invalid_type':
      return 'manquant ou invalide';
    case 'invalid_value':
      return 'valeur non prévue';
  }
  return issue.message;
}

/** Une phrase pour le premier problème : « Date de semis : date invalide (jour, mois, année attendus). » */
export function validationMessage(error: z.ZodError): string {
  const issue = error.issues[0];
  if (!issue) return 'Fiche invalide : vérifiez-la puis enregistrez à nouveau.';
  const label = where(issue.path);
  const text = what(issue);
  return label ? `${label} : ${text}.` : `Fiche invalide : ${text}.`;
}
