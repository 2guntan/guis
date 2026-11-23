'use client';

// Repris de Fieldproof (components/map/ParcelsMapCanvas.tsx), lui-même adapté d'Agriva : imagerie satellite,
// plusieurs champs, étiquettes. Guis : couleur par statut, clic vers la fiche du champ, centre sur les Niayes.
import 'leaflet/dist/leaflet.css';
import { useEffect, useRef } from 'react';
import L from 'leaflet';
import type { GeoJsonObject } from 'geojson';
import { IMAGERY_ATTRIBUTION, IMAGERY_URL, LABELS_URL, PARCEL_INVALID_STYLE, PARCEL_STYLE } from '@/lib/map';
import { NIAYES } from '@/lib/map';

export type MapParcel = { id: string; name?: string | null; geometry: unknown; invalid?: boolean; label?: string; color?: string; href?: string };

export default function ParcelsMapCanvas({ parcels, className, interactive = true, point }: {
  parcels: MapParcel[]; className?: string; interactive?: boolean; point?: { lat: number; lng: number } | null;
}) {
  const el = useRef<HTMLDivElement>(null);
  const key = JSON.stringify(parcels.map((p) => [p.id, p.geometry, p.invalid, p.color])) + JSON.stringify(point ?? null);
  useEffect(() => {
    if (!el.current) return;
    const map = L.map(el.current, {
      zoomControl: interactive, dragging: interactive, scrollWheelZoom: false, doubleClickZoom: interactive,
      touchZoom: interactive, boxZoom: false, keyboard: interactive, attributionControl: true,
    });
    L.tileLayer(IMAGERY_URL, { attribution: IMAGERY_ATTRIBUTION, maxZoom: 19, maxNativeZoom: 17 }).addTo(map);
    L.tileLayer(LABELS_URL, { maxZoom: 19, maxNativeZoom: 17, opacity: 0.8 }).addTo(map);
    const group = L.featureGroup().addTo(map);
    for (const p of parcels) {
      if (!p.geometry) continue;
      const style = p.invalid ? PARCEL_INVALID_STYLE : p.color ? { ...PARCEL_STYLE, color: p.color, fillColor: p.color } : PARCEL_STYLE;
      const layer = L.geoJSON(p.geometry as GeoJsonObject, { style });
      if (p.label || p.name) layer.bindTooltip(p.label ?? p.name ?? '', { permanent: parcels.length > 1 && parcels.length <= 30, direction: 'center', className: 'parcel-label' });
      if (p.href) layer.on('click', () => window.location.assign(p.href!));
      layer.addTo(group);
    }
    if (point) L.circleMarker([point.lat, point.lng], { radius: 6, color: '#fff', weight: 2, fillColor: '#3E6E8E', fillOpacity: 1 }).addTo(group);
    const b = group.getBounds();
    if (b.isValid()) map.fitBounds(b.pad(0.35), { maxZoom: 17 });
    else map.setView(NIAYES, 10);
    return () => { map.remove(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, interactive]);
  return <div ref={el} className={className ?? 'h-64 w-full'} />;
}
