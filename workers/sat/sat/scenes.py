"""Lecture du NDVI Sentinel-2 L2A d'un champ, scène par scène.

Repris de Fieldproof (workers/sat/sat/retro.py) : accès anonyme à Microsoft Planetary Computer (STAC,
URLs signées par `planetary-computer`), lectures fenêtrées sur les COG B04, B08 et SCL, masque des nuages
et des ombres par SCL, décalage de la base de traitement 04.00. Changements pour Guis :
  * fenêtre de la date de semis moins 15 jours jusqu'à aujourd'hui, au plus une scène par jour
    (la moins nuageuse) — la logique hivernage / contre-saison et le verdict ne sont pas repris ;
  * marge intérieure de 5 m sur le contour pour ne pas mesurer la bordure ; si elle ne laisse aucun
    pixel, on garde le contour entier et le suivi devient « indicatif » (NOTE-CADRAGE.md §4) ;
  * le nombre de pixels clairs retenus est rendu avec la mesure.
"""

from __future__ import annotations

import math
import os
from datetime import date, datetime
from typing import Any

import numpy as np
import planetary_computer
import pystac_client
import rasterio
from rasterio.enums import Resampling
from rasterio.features import geometry_mask
from rasterio.warp import transform_geom
from rasterio.windows import Window, from_bounds
from rasterio.windows import bounds as window_bounds
from shapely.geometry import mapping, shape

STAC_URL = os.environ.get("STAC_URL", "https://planetarycomputer.microsoft.com/api/stac/v1")
COLLECTION = "sentinel-2-l2a"
MAX_SCENES = int(os.environ.get("SAT_MAX_SCENES", "80"))
MAX_TILE_CLOUD = float(os.environ.get("SAT_MAX_TILE_CLOUD", "80"))   # filtre catalogue (tuile entière)
MIN_CLEAR_FRACTION = 0.6         # part minimale de pixels clairs du champ pour retenir une scène
CLEAR_SCL = (4, 5)               # végétation, sol nu ; écartés : 3 ombre, 8-9 nuages, 10 cirrus (et le reste)
INNER_MARGIN_M = 5.0             # marge retirée sur le bord du contour

GDAL_ENV = dict(
    GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
    CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.tiff",
    GDAL_HTTP_MAX_RETRY="4",
    GDAL_HTTP_RETRY_DELAY="1",
    GDAL_HTTP_MULTIRANGE="YES",
    GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES",
    GDAL_CACHEMAX=32,
    VSI_CACHE=False,
)


def item_date(item) -> date:
    return item.datetime.date() if item.datetime else datetime.fromisoformat(item.properties["datetime"].replace("Z", "+00:00")).date()


def search(geometry: dict, start: date, end: date) -> list:
    catalog = pystac_client.Client.open(STAC_URL)
    found = catalog.search(collections=[COLLECTION], intersects=geometry, datetime=f"{start.isoformat()}/{end.isoformat()}",
                           query={"eo:cloud_cover": {"lt": MAX_TILE_CLOUD}}, max_items=500)
    return list(found.items())


def select_items(items: list, skip_dates: set[str] | None = None) -> list:
    """Au plus une scène par jour (la moins nuageuse), sans les dates déjà mesurées ; au plus MAX_SCENES."""
    by_day: dict[date, Any] = {}
    for it in items:
        d = item_date(it)
        if skip_dates and d.isoformat() in skip_dates:
            continue
        cur = by_day.get(d)
        if cur is None or it.properties.get("eo:cloud_cover", 100) < cur.properties.get("eo:cloud_cover", 100):
            by_day[d] = it
    chosen = [by_day[d] for d in sorted(by_day)]
    return chosen[-MAX_SCENES:]


def _offset(item) -> float:
    # Depuis la base de traitement 04.00 (25/01/2022), les réflectances L2A portent un décalage de -1000.
    try:
        return -1000.0 if float(item.properties.get("s2:processing_baseline", "0")) >= 4.0 else 0.0
    except ValueError:
        return 0.0


def scene_ndvi(item, geom_wgs84: dict) -> dict | None:
    """NDVI moyen des pixels clairs du champ pour une scène, ou None si le champ est hors de l'image.

    Rend {date, ndvi (None si trop nuageux), cloud_pct, pixels, buffered, scene_id}."""
    item = planetary_computer.sign(item)
    with rasterio.Env(**GDAL_ENV):
        with rasterio.open(item.assets["B04"].href) as ds:
            geom = transform_geom("EPSG:4326", ds.crs, geom_wgs84)
            minx, miny, maxx, maxy = shape(geom).bounds
            pad = 20.0
            win = from_bounds(minx - pad, miny - pad, maxx + pad, maxy + pad, transform=ds.transform)
            c0, r0 = math.floor(win.col_off), math.floor(win.row_off)
            win = Window(c0, r0, math.ceil(win.col_off + win.width) - c0, math.ceil(win.row_off + win.height) - r0)
            try:
                win = win.intersection(Window(0, 0, ds.width, ds.height))
            except Exception:
                return None
            red = ds.read(1, window=win).astype("float32")
            wtransform = ds.window_transform(win)
            wb = window_bounds(win, ds.transform)
        with rasterio.open(item.assets["B08"].href) as ds:
            nir = ds.read(1, window=win).astype("float32")
        with rasterio.open(item.assets["SCL"].href) as ds:
            sw = from_bounds(*wb, transform=ds.transform)
            scl = ds.read(1, window=sw, out_shape=red.shape, resampling=Resampling.nearest, boundless=True, fill_value=0)

    # Marge intérieure de 5 m (le CRS de l'image est en mètres, UTM).
    inner = shape(geom).buffer(-INNER_MARGIN_M)
    buffered = not inner.is_empty
    inside = geometry_mask([mapping(inner)], out_shape=red.shape, transform=wtransform, invert=True) if buffered else None
    if inside is None or inside.sum() == 0:
        buffered = False
        inside = geometry_mask([geom], out_shape=red.shape, transform=wtransform, invert=True, all_touched=False)
        if inside.sum() < 4:   # champ minuscule : on prend tout pixel touché
            inside = geometry_mask([geom], out_shape=red.shape, transform=wtransform, invert=True, all_touched=True)
    valid = inside & (red > 0) & (nir > 0) & (scl > 0)
    n_valid = int(valid.sum())
    if n_valid == 0:
        return None
    clear = valid & np.isin(scl, CLEAR_SCL)
    n_clear = int(clear.sum())
    cloud_pct = round(100.0 * (1 - n_clear / n_valid), 1)
    out = {"date": item_date(item).isoformat(), "ndvi": None, "cloud_pct": cloud_pct, "pixels": n_clear, "buffered": buffered,
           "scene_id": item.id}
    if n_clear / n_valid < MIN_CLEAR_FRACTION:
        return out
    off = _offset(item)
    r = np.clip((red[clear] + off) / 10000.0, 0, None)
    n = np.clip((nir[clear] + off) / 10000.0, 0, None)
    s = n + r
    ok = s > 0
    if ok.any():
        out["ndvi"] = round(float(np.mean((n[ok] - r[ok]) / s[ok])), 4)
    return out


def square(lat: float, lng: float, side_m: float = 100.0) -> dict:
    dlat = side_m / 111_320 / 2
    dlng = side_m / (111_320 * math.cos(math.radians(lat))) / 2
    ring = [[lng - dlng, lat + dlat], [lng + dlng, lat + dlat], [lng + dlng, lat - dlat], [lng - dlng, lat - dlat], [lng - dlng, lat + dlat]]
    return {"type": "Polygon", "coordinates": [ring]}


if __name__ == "__main__":   # essai local sans base : python -m sat.scenes 14.95 -16.95 2026-10-01 [côté_m]
    import json
    import sys
    import time
    from datetime import timedelta

    from .status import field_status

    lat, lng = float(sys.argv[1]), float(sys.argv[2])
    sown = date.fromisoformat(sys.argv[3])
    side = float(sys.argv[4]) if len(sys.argv) > 4 else 100.0
    t0 = time.time()
    g = square(lat, lng, side)
    items = select_items(search(g, sown - timedelta(days=15), date.today()))
    series = [r for r in (scene_ndvi(it, g) for it in items) if r]
    status = field_status(sown, series, date.today(), side * side / 10_000, all(p["buffered"] for p in series) if series else True)
    print(json.dumps({"scenes": len(items), "series": series, "status": status, "s": round(time.time() - t0, 1)}, ensure_ascii=False, indent=1))
