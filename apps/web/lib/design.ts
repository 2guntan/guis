// Couleurs et libellés de la direction B (docs/design/SPECS.md).
import type { FieldStatus } from '@/lib/labels';

/** Rampe NDVI de la carte et de la légende web (remplace les couleurs de statut de l'app côté web). */
export const STATUS_FILL: Record<FieldStatus, string | null> = {
  none: null, // pas de remplissage, contour pointillé
  waiting: '#D5D8D0',
  bare: '#B49A74',
  emergence: '#A9C47F',
  growth: '#5E9B4E',
  peak: '#1F5E33',
  senescence: '#C9A24A',
};

export const STATUS_ORDER: FieldStatus[] = ['none', 'waiting', 'bare', 'emergence', 'growth', 'peak', 'senescence'];

export const STATUS_SHORT: Record<FieldStatus, string> = {
  none: 'Sans contour',
  waiting: 'En attente d’images',
  bare: 'Semé, sol nu',
  emergence: 'Levée',
  growth: 'En croissance',
  peak: 'Pic',
  senescence: 'Sénescence',
};

/** Couleur d'une valeur de NDVI (vignettes « le champ à chaque passage »). */
export function ndviFill(v: number | null): string | null {
  if (v === null) return null;
  if (v < 0.25) return '#B49A74';
  if (v < 0.35) return '#A9C47F';
  if (v < 0.55) return '#5E9B4E';
  return '#1F5E33';
}

export const ALERT_YELLOW = '#E0A100';

/** Étiquette courte d'une alerte (tableau des champs) : « Pas de levée à J+35 », « Baisse NDVI 0,16 »… */
export function alertTag(a: { code: string; message: string }): string {
  if (a.code === 'no_emergence') return 'Pas de levée à J+35';
  if (a.code === 'green_at_sowing') return 'Déjà vert au semis';
  if (a.code === 'ndvi_drop') {
    const m = a.message.match(/de (\d+,\d+)/);
    return m ? `Baisse NDVI ${m[1]}` : 'Baisse NDVI';
  }
  return a.message;
}

/** Message d'une alerte tel qu'affiché dans la liste « à vérifier » (sans la partie « à vérifier »). */
export function alertSentence(a: { code: string; message: string }): string {
  if (a.code === 'no_emergence') {
    const d = a.message.match(/J\+(\d+)/);
    return `Pas de levée ${d ? `${d[1]} jours` : '35 jours'} après le semis.`;
  }
  if (a.code === 'green_at_sowing') return 'Déjà vert à la date de semis déclarée. Vérifier la date ou le contour.';
  if (a.code === 'ndvi_drop') {
    const m = a.message.match(/de (\d+,\d+)/);
    return `NDVI en baisse${m ? ` de ${m[1]}` : ''}. Stress hydrique ou maladie possible.`;
  }
  return a.message;
}

/** Saison de pomme de terre affichée : novembre à juin. */
export function campaignLabel(now = new Date()) {
  const y = now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1;
  return `Campagne pomme de terre ${y}-${y + 1}`;
}

export function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
}
