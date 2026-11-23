// Repris de Fieldproof (lib/map.ts). Fonds de carte. Esri World Imagery (imagerie satellite, sans clé, attribution requise) pour voir la parcelle ;
// OpenStreetMap en repli.
export const IMAGERY_URL = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
export const IMAGERY_ATTRIBUTION = 'Imagerie © Esri, Maxar, Earthstar Geographics';
export const LABELS_URL = 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
export const OSM_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
export const OSM_ATTRIBUTION = '&copy; contributeurs OpenStreetMap';

export const PARCEL_STYLE = { color: '#D9A23F', weight: 2.5, fillColor: '#D9A23F', fillOpacity: 0.18 };
export const PARCEL_INVALID_STYLE = { color: '#E06A4E', weight: 2.5, fillColor: '#E06A4E', fillOpacity: 0.2, dashArray: '6 4' };
export const OTHER_PARCEL_STYLE = { color: '#FFFDF7', weight: 1.5, fillOpacity: 0.06, dashArray: '4 4' };

/** Centre par défaut : la zone des Niayes, entre Thiès et Mboro (NOTE-CADRAGE.md §7). */
export const NIAYES: [number, number] = [14.95, -16.95];
