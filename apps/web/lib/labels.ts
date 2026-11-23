// Listes fermées partagées avec l'app Android (bootstrap) et libellés du tableau de bord.

export const IRRIGATION = ['Goutte-à-goutte', 'Aspersion', 'Raie', 'Arrosoir', 'Autre'] as const;
export const WATER_SOURCES = ['Puits', 'Forage', 'Céane', 'Bassin', 'Réseau', 'Autre'] as const;
export const SEXES = { F: 'Femme', H: 'Homme' } as const;

export const FIELD_STATUS = {
  none: 'Sans contour',
  waiting: 'En attente d’images',
  bare: 'Semé, sol nu',
  emergence: 'Levée',
  growth: 'En croissance',
  peak: 'Pic',
  senescence: 'Sénescence / récolte',
} as const;
export type FieldStatus = keyof typeof FIELD_STATUS;

export const STATUS_TONE: Record<FieldStatus, 'neutral' | 'sky' | 'ochre' | 'forest' | 'clay'> = {
  none: 'neutral',
  waiting: 'neutral',
  bare: 'ochre',
  emergence: 'sky',
  growth: 'forest',
  peak: 'forest',
  senescence: 'ochre',
};

export const ALERTS = {
  no_emergence: 'Pas de levée à J+35',
  ndvi_drop: 'Chute de NDVI',
  green_at_sowing: 'Déjà vert au semis',
} as const;
