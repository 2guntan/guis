'use client';

import 'leaflet/dist/leaflet.css';
import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import L from 'leaflet';
import type { GeoJsonObject } from 'geojson';
import { Check, Crosshair, Footprints, Hand, Pause, Play, RotateCcw, Trash2, X } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import type { GpsPoint, Polygon } from '@/lib/draft';
import { IMAGERY_ATTRIBUTION, IMAGERY_URL, LABELS_URL, OTHER_PARCEL_STYLE, PARCEL_INVALID_STYLE, PARCEL_STYLE } from '@/lib/map';
import { ZIGUINCHOR, areaHa, distanceM, fmtArea, localGeometryWarning, medianAccuracy, polygonFrom, verticesOf } from '@/lib/geo';

export type CaptureResult = {
  geometry: Polygon | null;
  points: GpsPoint[];
  precision_m: number | null;
  captured_at: string;
  source: 'agent_walk' | 'agent_corners';
};

type Mode = 'walk' | 'tap';
const MIN_STEP_M = 2.5;
const MAX_ACCURACY_M = 30;

export default function ParcelCaptureCanvas({
  name, initial, initialPoints, initialSource, others, onDone, onCancel,
}: {
  name: string;
  initial: Polygon | null;
  initialPoints: GpsPoint[];
  initialSource: 'agent_walk' | 'agent_corners' | null;
  others: { id: string; geometry: Polygon | null; name: string }[];
  onDone: (r: CaptureResult) => void;
  onCancel: () => void;
}) {
  const el = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const shapeRef = useRef<L.LayerGroup | null>(null);
  const meRef = useRef<L.Marker | null>(null);
  const meCircleRef = useRef<L.Circle | null>(null);
  const watchRef = useRef<number | null>(null);
  const [mode, setMode] = useState<Mode>(initialSource === 'agent_walk' ? 'walk' : 'tap');
  const [vertices, setVertices] = useState<GpsPoint[]>(() => {
    if (initialPoints?.length >= 3) return initialPoints;
    return verticesOf(initial).map((v) => ({ ...v, accuracy_m: null, captured_at: new Date().toISOString() }));
  });
  const [walking, setWalking] = useState(false);
  const [fix, setFix] = useState<{ lat: number; lng: number; accuracy: number } | null>(null);
  const modeRef = useRef(mode);
  modeRef.current = mode;

  const poly = polygonFrom(vertices);
  const area = areaHa(poly);
  const warning = localGeometryWarning(poly);

  // Carte
  useEffect(() => {
    if (!el.current) return;
    const map = L.map(el.current, { zoomControl: false, attributionControl: true, tapTolerance: 20 } as L.MapOptions);
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    L.tileLayer(IMAGERY_URL, { attribution: IMAGERY_ATTRIBUTION, maxZoom: 20, maxNativeZoom: 17 }).addTo(map);
    L.tileLayer(LABELS_URL, { maxZoom: 20, maxNativeZoom: 17, opacity: 0.75 }).addTo(map);
    const others_ = L.featureGroup().addTo(map);
    for (const o of others) if (o.geometry) L.geoJSON(o.geometry as GeoJsonObject, { style: OTHER_PARCEL_STYLE }).bindTooltip(o.name, { className: 'parcel-label' }).addTo(others_);
    shapeRef.current = L.layerGroup().addTo(map);
    mapRef.current = map;

    const start = polygonFrom(vertices);
    if (start) map.fitBounds(L.geoJSON(start as GeoJsonObject).getBounds().pad(0.6), { maxZoom: 19 });
    else if (others_.getBounds().isValid()) map.fitBounds(others_.getBounds().pad(0.8), { maxZoom: 18 });
    else {
      map.setView(ZIGUINCHOR, 16);
      navigator.geolocation?.getCurrentPosition(
        (p) => map.setView([p.coords.latitude, p.coords.longitude], 18),
        () => undefined,
        { enableHighAccuracy: true, timeout: 8000, maximumAge: 30000 },
      );
    }

    map.on('click', (e: L.LeafletMouseEvent) => {
      if (modeRef.current !== 'tap') return;
      setVertices((v) => [...v, { lat: e.latlng.lat, lng: e.latlng.lng, accuracy_m: null, captured_at: new Date().toISOString() }]);
    });
    return () => {
      if (watchRef.current !== null) navigator.geolocation.clearWatch(watchRef.current);
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Dessin du contour et des sommets
  useEffect(() => {
    const g = shapeRef.current;
    if (!g) return;
    g.clearLayers();
    const latlngs = vertices.map((v) => L.latLng(v.lat, v.lng));
    if (latlngs.length >= 3) L.polygon(latlngs, warning ? PARCEL_INVALID_STYLE : PARCEL_STYLE).addTo(g);
    else if (latlngs.length === 2) L.polyline(latlngs, { color: PARCEL_STYLE.color, weight: 2.5, dashArray: '6 4' }).addTo(g);
    const showMarkers = mode === 'tap' || vertices.length <= 40;
    if (showMarkers) {
      vertices.forEach((v, i) => {
        const size = mode === 'tap' ? 20 : 10;
        const m = L.marker([v.lat, v.lng], {
          draggable: mode === 'tap',
          icon: L.divIcon({ className: 'vertex-marker', iconSize: [size, size], html: mode === 'tap' ? `<span style="display:block;text-align:center;font:600 10px/16px var(--font-sans);color:#8A5F14">${i + 1}</span>` : '' }),
        });
        m.on('dragend', () => {
          const ll = m.getLatLng();
          setVertices((prev) => prev.map((p, j) => (j === i ? { ...p, lat: ll.lat, lng: ll.lng } : p)));
        });
        m.addTo(g);
      });
    }
  }, [vertices, mode, warning]);

  const showFix = useCallback((lat: number, lng: number, accuracy: number) => {
    const map = mapRef.current;
    if (!map) return;
    if (!meRef.current) {
      meRef.current = L.marker([lat, lng], { icon: L.divIcon({ className: 'gps-dot', iconSize: [16, 16] }), interactive: false }).addTo(map);
      meCircleRef.current = L.circle([lat, lng], { radius: accuracy, color: '#3E6E8E', weight: 1, fillOpacity: 0.1, interactive: false }).addTo(map);
    } else {
      meRef.current.setLatLng([lat, lng]);
      meCircleRef.current?.setLatLng([lat, lng]).setRadius(accuracy);
    }
  }, []);

  function startWalk() {
    if (!navigator.geolocation) {
      toast.error('Le GPS n’est pas disponible sur cet appareil. Placez les sommets sur la carte.');
      setMode('tap');
      return;
    }
    setWalking(true);
    watchRef.current = navigator.geolocation.watchPosition(
      (p) => {
        const { latitude: lat, longitude: lng, accuracy } = p.coords;
        setFix({ lat, lng, accuracy });
        showFix(lat, lng, accuracy);
        mapRef.current?.panTo([lat, lng], { animate: true });
        if (accuracy > MAX_ACCURACY_M) return;
        setVertices((v) => {
          const last = v[v.length - 1];
          if (last && distanceM(last, { lat, lng }) < MIN_STEP_M) return v;
          return [...v, { lat, lng, accuracy_m: Math.round(accuracy * 10) / 10, captured_at: new Date(p.timestamp).toISOString() }];
        });
      },
      (err) => {
        toast.error(err.code === 1 ? 'Accès à la position refusé. Autorisez la localisation, ou placez les sommets sur la carte.' : 'Signal GPS indisponible pour le moment.');
        stopWalk();
      },
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 },
    );
  }
  function stopWalk() {
    if (watchRef.current !== null) navigator.geolocation.clearWatch(watchRef.current);
    watchRef.current = null;
    setWalking(false);
  }
  function locate() {
    navigator.geolocation?.getCurrentPosition(
      (p) => {
        setFix({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy });
        showFix(p.coords.latitude, p.coords.longitude, p.coords.accuracy);
        mapRef.current?.setView([p.coords.latitude, p.coords.longitude], 18);
      },
      () => toast.error('Position indisponible.'),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }
  function finish() {
    stopWalk();
    if (vertices.length > 0 && vertices.length < 3) {
      toast.error('Il faut au moins 3 sommets pour fermer le contour.');
      return;
    }
    onDone({
      geometry: polygonFrom(vertices),
      points: vertices,
      precision_m: mode === 'walk' ? medianAccuracy(vertices) : null,
      captured_at: new Date().toISOString(),
      source: mode === 'walk' ? 'agent_walk' : 'agent_corners',
    });
  }

  const accTone = !fix ? '' : fix.accuracy <= 5 ? 'text-forest-100' : fix.accuracy <= 15 ? 'text-ochre-100' : 'text-clay-50';

  return createPortal(
    <div className="fixed inset-0 z-[1100] flex flex-col bg-forest-900 text-paper">
      <div className="flex items-center gap-3 px-4 py-3">
        <button onClick={() => { stopWalk(); onCancel(); }} className="rounded-full p-2 hover:bg-forest-800" aria-label="Annuler"><X className="h-5 w-5" /></button>
        <div className="min-w-0 flex-1">
          <div className="truncate font-display text-lg">{name || 'Parcelle'}</div>
          <div className="text-xs text-forest-100/70">{mode === 'walk' ? 'Contour marché' : 'Sommets placés'}</div>
        </div>
        <div className="flex rounded-lg bg-forest-800 p-0.5 text-sm">
          <button onClick={() => { stopWalk(); setMode('walk'); }} className={cn('inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5', mode === 'walk' && 'bg-paper text-forest-900')}><Footprints className="h-4 w-4" />Marcher</button>
          <button onClick={() => { stopWalk(); setMode('tap'); }} className={cn('inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5', mode === 'tap' && 'bg-paper text-forest-900')}><Hand className="h-4 w-4" />Sommets</button>
        </div>
      </div>

      <div className="relative flex-1">
        <div ref={el} className="absolute inset-0" />
        <div className="pointer-events-none absolute inset-x-3 top-3 z-[500] flex flex-col items-start gap-2">
          <div className="pointer-events-auto rounded-xl bg-forest-900/85 px-3 py-2 text-sm backdrop-blur">
            {mode === 'walk'
              ? walking ? 'Marchez le long de la limite de la parcelle. Les points s’ajoutent tous les 2,5 m.' : 'Placez-vous à un angle de la parcelle, puis démarrez.'
              : 'Touchez la carte à chaque angle de la parcelle, dans l’ordre. Faites glisser un sommet pour le corriger.'}
          </div>
          {fix && (
            <div className={cn('pointer-events-auto rounded-full bg-forest-900/85 px-3 py-1 text-xs backdrop-blur', accTone)}>
              Précision GPS ± {Math.round(fix.accuracy)} m{fix.accuracy > MAX_ACCURACY_M ? ' — trop faible, point ignoré' : ''}
            </div>
          )}
          {warning && <div className="pointer-events-auto rounded-xl bg-clay-500 px-3 py-2 text-sm text-white">{warning}</div>}
        </div>
        <button onClick={locate} className="absolute bottom-8 right-2.5 z-[500] rounded-lg bg-surface p-2.5 text-forest-800 shadow-lift" aria-label="Ma position">
          <Crosshair className="h-5 w-5" />
        </button>
      </div>

      <div className="relative z-[600] -mt-5 rounded-t-[22px] bg-surface px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-2.5 text-ink shadow-[0_-18px_40px_-24px_rgba(15,42,31,0.6)]">
        <div className="mx-auto h-1 w-9 rounded-full bg-sand-300" />
        <div className="mt-3 flex items-end justify-between gap-3">
          <div>
            <p className="eyebrow text-ink-faint">Surface relevée</p>
            <p className="font-display text-[38px] leading-[1.1] tracking-tight text-forest-900 tabular">{vertices.length >= 3 ? fmtArea(area) : '—'}</p>
          </div>
          <div className="pb-1 text-right text-[13px] text-ink-soft">
            <div>{vertices.length} sommet{vertices.length > 1 ? 's' : ''}</div>
            {fix && <div>GPS ± {Math.round(fix.accuracy)} m</div>}
          </div>
        </div>
        <div className="mt-3 grid grid-cols-[auto_auto_1fr] gap-2">
        <Button variant="secondary" size="lg" className="px-4" aria-label="Retirer le dernier sommet" onClick={() => setVertices((v) => v.slice(0, -1))} disabled={!vertices.length}><RotateCcw className="h-5 w-5" /></Button>
        <Button variant="secondary" size="lg" className="px-4" aria-label="Tout effacer" onClick={() => { if (confirm('Effacer tous les sommets de ce contour ?')) setVertices([]); }} disabled={!vertices.length}><Trash2 className="h-5 w-5" /></Button>
        {mode === 'walk' && !walking && vertices.length < 3 ? (
          <Button size="lg" onClick={startWalk}><Play className="h-5 w-5" />{vertices.length ? 'Reprendre' : 'Démarrer le tracé'}</Button>
        ) : mode === 'walk' && walking ? (
          <div className="grid grid-cols-2 gap-2">
            <Button size="lg" variant="secondary" onClick={stopWalk}><Pause className="h-5 w-5" />Pause</Button>
            <Button size="lg" onClick={finish} disabled={vertices.length < 3}><Check className="h-5 w-5" />Fermer</Button>
          </div>
        ) : (
          <div className={cn('grid gap-2', mode === 'walk' ? 'grid-cols-2' : 'grid-cols-1')}>
            {mode === 'walk' && <Button size="lg" variant="secondary" onClick={startWalk}><Play className="h-5 w-5" />Reprendre</Button>}
            <Button size="lg" onClick={finish} disabled={vertices.length > 0 && vertices.length < 3}><Check className="h-5 w-5" />Valider le contour</Button>
          </div>
        )}
        </div>
      </div>
    </div>,
    document.body,
  );
}
