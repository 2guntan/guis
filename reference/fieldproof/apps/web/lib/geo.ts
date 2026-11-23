import turfArea from '@turf/area';
import kinks from '@turf/kinks';
import type { Feature, Polygon as GJPolygon } from 'geojson';
import type { GpsPoint, Polygon } from '@/lib/draft';

export const ZIGUINCHOR: [number, number] = [12.5605, -16.2719];

export function polygonFrom(points: { lat: number; lng: number }[]): Polygon | null {
  if (points.length < 3) return null;
  const ring = points.map((p) => [round(p.lng), round(p.lat)]);
  ring.push([...ring[0]]);
  return { type: 'Polygon', coordinates: [ring] };
}

const round = (v: number) => Math.round(v * 1e7) / 1e7;

export function areaHa(poly: Polygon | null): number | null {
  if (!poly) return null;
  try {
    return turfArea(poly as GJPolygon) / 10000;
  } catch {
    return null;
  }
}

export function selfIntersects(poly: Polygon | null): boolean {
  if (!poly || poly.coordinates[0].length < 5) return false;
  try {
    const f: Feature<GJPolygon> = { type: 'Feature', properties: {}, geometry: poly as GJPolygon };
    return kinks(f).features.length > 0;
  } catch {
    return false;
  }
}

/** Avertissements côté appareil ; la base fait foi (geometry_invalid_reason). */
export function localGeometryWarning(poly: Polygon | null): string | null {
  if (!poly) return null;
  if (selfIntersects(poly)) return 'Le contour se croise : reprenez l’ordre des sommets.';
  const a = areaHa(poly) ?? 0;
  if (a * 10000 < 100) return 'Surface inférieure à 100 m² : contour trop petit.';
  if (a > 500) return 'Surface supérieure à 500 ha : vérifiez le contour.';
  return null;
}

export function distanceM(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

export function medianAccuracy(points: GpsPoint[]): number | null {
  const v = points.map((p) => p.accuracy_m).filter((x): x is number => typeof x === 'number').sort((a, b) => a - b);
  if (!v.length) return null;
  return Math.round(v[Math.floor(v.length / 2)] * 10) / 10;
}

/** Sommets d'un polygone (sans le point de fermeture). */
export function verticesOf(poly: Polygon | null): { lat: number; lng: number }[] {
  if (!poly) return [];
  const ring = poly.coordinates[0] ?? [];
  return ring.slice(0, -1).map(([lng, lat]) => ({ lat, lng }));
}

export function fmtArea(ha: number | null) {
  if (ha === null) return '—';
  if (ha < 1) return `${Math.round(ha * 10000).toLocaleString('fr-FR')} m²`;
  return `${ha.toLocaleString('fr-FR', { maximumFractionDigits: 2 })} ha`;
}
