// Repris de Fieldproof (lib/map.ts). Fonds de carte. Esri World Imagery (imagerie satellite, sans clé, attribution requise) pour voir la parcelle ;
// OpenStreetMap en repli.
export const IMAGERY_URL = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
export const IMAGERY_ATTRIBUTION = 'Imagerie © Esri, Maxar, Earthstar Geographics';

/** Centre par défaut : la zone des Niayes, entre Thiès et Mboro (NOTE-CADRAGE.md §7). */
export const NIAYES: [number, number] = [14.95, -16.95];
