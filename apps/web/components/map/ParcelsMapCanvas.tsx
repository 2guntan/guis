'use client';

// Repris de Fieldproof (components/map/ParcelsMapCanvas.tsx), lui-même adapté d'Agriva : imagerie satellite,
// plusieurs champs, étiquettes. Guis, direction B : remplissage par la rampe NDVI, contour pointillé sans
// remplissage pour un champ sans statut, anneau jaune autour d'un champ à vérifier, sommets et marge de 5 m
// pour la fiche d'un champ, clic vers la fiche.
import 'leaflet/dist/leaflet.css';
import { useEffect, useRef } from 'react';
import L from 'leaflet';
import type { GeoJsonObject } from 'geojson';
import { IMAGERY_ATTRIBUTION, IMAGERY_URL, NIAYES } from '@/lib/map';

export type MapParcel = {
  id: string;
  geometry: unknown;
  /** Couleur de remplissage ; null : contour pointillé sans remplissage. */
  fill?: string | null;
  label?: string;
  href?: string;
  alert?: boolean;
  /** Champ de la fiche : trait épais, sommets visibles, marge intérieure de 5 m en pointillés. */
  focus?: boolean;
  inner?: unknown;
};

const ALERT = '#E0A100';

export default function ParcelsMapCanvas({ parcels, className, interactive = true }: { parcels: MapParcel[]; className?: string; interactive?: boolean }) {
  const el = useRef<HTMLDivElement>(null);
  const key = JSON.stringify(parcels.map((p) => [p.id, p.geometry, p.fill, p.alert, p.focus]));
  useEffect(() => {
    if (!el.current) return;
    const map = L.map(el.current, {
      zoomControl: interactive,
      dragging: interactive,
      scrollWheelZoom: interactive,
      doubleClickZoom: interactive,
      touchZoom: interactive,
      boxZoom: false,
      keyboard: interactive,
      attributionControl: true,
    });
    if (interactive) map.zoomControl.setPosition('topright');
    L.tileLayer(IMAGERY_URL, { attribution: IMAGERY_ATTRIBUTION, maxZoom: 19, maxNativeZoom: 17 }).addTo(map);
    const group = L.featureGroup().addTo(map);
    const focusGroup = L.featureGroup();
    for (const p of parcels) {
      if (!p.geometry) continue;
      const style: L.PathOptions =
        p.fill === null || p.fill === undefined
          ? { color: '#163A2C', weight: 1.5, dashArray: '4 4', fill: false }
          : { color: '#FFFFFF', weight: p.focus ? 3 : 1.5, fillColor: p.fill, fillOpacity: p.focus ? 0.85 : 0.9 };
      const layer = L.geoJSON(p.geometry as GeoJsonObject, { style });
      if (p.label) layer.bindTooltip(p.label, { direction: 'top', className: 'parcel-label' });
      if (p.href) layer.on('click', () => window.location.assign(p.href!));
      layer.addTo(p.focus ? focusGroup : group);
      if (p.alert) {
        L.circleMarker(layer.getBounds().getCenter(), { radius: 22, color: ALERT, weight: 4, fill: false, interactive: false }).addTo(group);
      }
      if (p.focus) {
        if (p.inner) L.geoJSON(p.inner as GeoJsonObject, { style: { color: '#FFFFFF', weight: 1.5, dashArray: '5 5', fill: false } }).addTo(focusGroup);
        const g = p.geometry as { type: string; coordinates: number[][][] };
        if (g.type === 'Polygon') {
          for (const [lng, lat] of g.coordinates[0].slice(0, -1)) {
            L.circleMarker([lat, lng], { radius: 6, color: '#163A2C', weight: 2, fillColor: '#FFFFFF', fillOpacity: 1 }).addTo(focusGroup);
          }
        }
      }
    }
    focusGroup.addTo(map);
    const target = focusGroup.getLayers().length ? focusGroup.getBounds() : group.getBounds();
    if (target.isValid()) map.fitBounds(target.pad(focusGroup.getLayers().length ? 0.6 : 0.15), { maxZoom: 18 });
    else map.setView(NIAYES, 10);
    return () => {
      map.remove();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, interactive]);
  return <div ref={el} className={className ?? 'h-64 w-full'} />;
}
