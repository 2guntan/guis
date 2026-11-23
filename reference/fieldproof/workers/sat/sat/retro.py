"""Analyse rétroactive d'une parcelle (CONTEXT.md, module Watch) sur Sentinel-2 L2A, complétée par le
radar Sentinel-1 (module radar, ADR-0010).

Source : Microsoft Planetary Computer (STAC, accès anonyme, URLs signées par `planetary-computer`).
Pour chaque scène retenue on lit B04 (rouge), B08 (proche infrarouge) et SCL (classification) en
lectures fenêtrées sur les COG, découpées au contour de la parcelle reprojeté dans le CRS de l'image ;
nuages et ombres sont masqués par SCL ; on garde la moyenne du NDVI des pixels clairs.

Saisons (Sénégal) : hivernage du 1er juin au 30 novembre ; contre-saison du 1er décembre au 31 mai. Juin est
dans l'hivernage pour que la ligne de base voie le sol nu avant semis : en Casamance les pluies arrivent dès juin
et juillet est souvent couvert (calibration zone Sud, 21/11/2026 : hivernage 2025 « couvert permanent » sur 21
sites sur 24 avec un début au 1er juillet, cultivé sur 23 avec un début au 1er juin).
On analyse les 3 dernières saisons terminées avant la date du jour.

Heuristique de culture (par saison) — volontairement simple et explicable au prêteur :
  * il faut au moins MIN_CLEAR_SCENES scènes claires (≥ 60 % des pixels de la parcelle visibles), sinon
    la saison est « incertaine » (fréquent en Casamance en hivernage : couverture nuageuse) ;
  * ligne de base = 20e centile du NDVI de la saison (sol nu ou chaume avant semis) ;
  * saison cultivée si le pic de NDVI ≥ 0,35, s'il dépasse la ligne de base d'au moins 0,15 ET s'il
    est précédé dans la saison d'une valeur plus basse d'au moins 0,15 : une culture annuelle se voit comme
    une montée puis une chute de la végétation ;
  * pic en début de saison suivi d'une baisse seulement (végétation restante de l'hivernage en décembre) :
    non cultivée (calibration zone Sud, 21/11/2026 : 50 des 65 contre-saisons « cultivées » sans cette
    règle avaient leur pic en décembre) ;
  * pic ≥ 0,35 mais sans montée (ligne de base déjà ≥ 0,35) : couvert permanent (verger, arbres,
    végétation naturelle) — non concluant pour une culture annuelle → « incertaine » ;
  * sinon : non cultivée.
Option A (ADR-0010) : une saison que Sentinel-2 ne peut pas trancher faute d'images claires (« incertaine »)
est tranchée par le radar Sentinel-1, qui voit à travers les nuages ; quand l'optique voit, elle garde la main.
Chaque saison porte sa source (« optical », « radar » ou null) et les indicateurs radar.
Verdict de la parcelle : fondé sur l'hivernage, voir verdict_of (une contre-saison vide est normale en culture
pluviale).
Surface confirmée = surface GPS de la parcelle si au moins une saison est cultivée (cultivée ou
partiellement cultivée), sinon nulle : l'analyse est faite au contour relevé, pas sur une détection de bord.
"""

from __future__ import annotations

import math
import os
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
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
from shapely.geometry import shape

from . import radar

STAC_URL = os.environ.get("STAC_URL", "https://planetarycomputer.microsoft.com/api/stac/v1")
COLLECTION = "sentinel-2-l2a"
PROVIDER = "planetary_computer:sentinel-2-l2a"
PROVIDER_WITH_RADAR = "planetary_computer:sentinel-2-l2a+sentinel-1-rtc"
RADAR_ENABLED = os.environ.get("SAT_RADAR", "1").strip() not in ("0", "false", "off")
MAX_SCENES = int(os.environ.get("SAT_MAX_SCENES", "40"))
MAX_TILE_CLOUD = float(os.environ.get("SAT_MAX_TILE_CLOUD", "80"))   # filtre catalogue (tuile entière)
READ_THREADS = int(os.environ.get("SAT_READ_THREADS", "4"))
BIN_DAYS = 15                    # une scène au plus par quinzaine et par saison
MIN_CLEAR_FRACTION = 0.6         # part minimale de pixels clairs pour retenir une scène
MIN_CLEAR_SCENES = 3
PEAK_THRESHOLD = 0.35
MIN_RISE = 0.15
CLEAR_SCL = (4, 5)               # végétation, sol nu ; écartés : 3 ombre, 8-9 nuages, 10 cirrus (et le reste)

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


@dataclass
class Season:
    label: str
    start: date
    end: date


def last_seasons(today: date, n: int = 3) -> list[Season]:
    out: list[Season] = []
    for y in range(today.year - 3, today.year + 1):
        out.append(Season(f"Hivernage {y}", date(y, 6, 1), date(y, 11, 30)))
        out.append(Season(f"Contre-saison {y}-{str(y + 1)[2:]}", date(y, 12, 1), date(y + 1, 5, 31)))
    ended = sorted((s for s in out if s.end < today), key=lambda s: s.end)
    return ended[-n:]


def _item_date(item) -> date:
    return item.datetime.date() if item.datetime else datetime.fromisoformat(item.properties["datetime"].replace("Z", "+00:00")).date()


def select_items(items: list, seasons: list[Season]) -> list[tuple[Season, Any]]:
    """Par saison et par quinzaine, la scène la moins nuageuse ; au plus MAX_SCENES au total."""
    chosen: list[tuple[Season, Any]] = []
    for s in seasons:
        bins: dict[int, Any] = {}
        for it in items:
            d = _item_date(it)
            if not (s.start <= d <= s.end):
                continue
            b = (d - s.start).days // BIN_DAYS
            cur = bins.get(b)
            if cur is None or it.properties.get("eo:cloud_cover", 100) < cur.properties.get("eo:cloud_cover", 100):
                bins[b] = it
        chosen += [(s, bins[k]) for k in sorted(bins)]
    if len(chosen) > MAX_SCENES:
        chosen.sort(key=lambda p: p[1].properties.get("eo:cloud_cover", 100))
        chosen = chosen[:MAX_SCENES]
    chosen.sort(key=lambda p: _item_date(p[1]))
    return chosen


def _offset(item) -> float:
    # Depuis la base de traitement 04.00 (25/01/2022), les réflectances L2A portent un décalage de -1000.
    try:
        return -1000.0 if float(item.properties.get("s2:processing_baseline", "0")) >= 4.0 else 0.0
    except ValueError:
        return 0.0


def scene_ndvi(item, geom_wgs84: dict) -> dict | None:
    """NDVI moyen des pixels clairs de la parcelle pour une scène, ou None si la parcelle est hors de l'image."""
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

    inside = geometry_mask([geom], out_shape=red.shape, transform=wtransform, invert=True, all_touched=False)
    if inside.sum() < 4:   # parcelle minuscule : on prend tout pixel touché
        inside = geometry_mask([geom], out_shape=red.shape, transform=wtransform, invert=True, all_touched=True)
    valid = inside & (red > 0) & (nir > 0) & (scl > 0)
    n_valid = int(valid.sum())
    if n_valid == 0:
        return None
    clear = valid & np.isin(scl, CLEAR_SCL)
    n_clear = int(clear.sum())
    cloud_pct = round(100.0 * (1 - n_clear / n_valid), 1)
    d = _item_date(item).isoformat()
    if n_clear / n_valid < MIN_CLEAR_FRACTION:
        return {"date": d, "ndvi": None, "cloud_pct": cloud_pct}
    off = _offset(item)
    r = np.clip((red[clear] + off) / 10000.0, 0, None)
    n = np.clip((nir[clear] + off) / 10000.0, 0, None)
    s = n + r
    ok = s > 0
    if not ok.any():
        return {"date": d, "ndvi": None, "cloud_pct": cloud_pct}
    ndvi = float(np.mean((n[ok] - r[ok]) / s[ok]))
    return {"date": d, "ndvi": round(ndvi, 4), "cloud_pct": cloud_pct}


def classify_season(s: Season, series: list[dict]) -> dict:
    pts = [p for p in series if p["ndvi"] is not None and s.start.isoformat() <= p["date"] <= s.end.isoformat()]
    considered = [p for p in series if s.start.isoformat() <= p["date"] <= s.end.isoformat()]
    out = {"label": s.label, "start": s.start.isoformat(), "end": s.end.isoformat(), "scenes_considered": len(considered),
           "cloud_free_scenes": len(pts), "ndvi_peak": None, "ndvi_peak_date": None, "ndvi_baseline": None, "cultivated": None,
           "status": "uncertain"}
    if not pts:
        return out
    peak = max(pts, key=lambda p: p["ndvi"])
    values = np.array([p["ndvi"] for p in pts])
    baseline = float(np.percentile(values, 20)) if len(values) >= 5 else float(values.min())
    out.update(ndvi_peak=round(peak["ndvi"], 3), ndvi_peak_date=peak["date"], ndvi_baseline=round(baseline, 3))
    if len(pts) < MIN_CLEAR_SCENES:
        return out
    i_peak = next(i for i, p in enumerate(pts) if p is peak)
    rise = peak["ndvi"] - min((p["ndvi"] for p in pts[:i_peak]), default=peak["ndvi"])
    if peak["ndvi"] >= PEAK_THRESHOLD and peak["ndvi"] - baseline >= MIN_RISE and rise >= MIN_RISE:
        out.update(cultivated=True, status="cultivated")
    elif peak["ndvi"] >= PEAK_THRESHOLD and peak["ndvi"] - baseline >= MIN_RISE:
        # pic dès le début de saison puis baisse : végétation restante de la saison précédente, pas un cycle
        out.update(cultivated=False, status="not_cultivated")
    elif peak["ndvi"] >= PEAK_THRESHOLD:
        out.update(status="permanent_vegetation")
    else:
        out.update(cultivated=False, status="not_cultivated")
    return out


def merge_radar(row: dict, r: dict | None) -> dict:
    """Option A : l'optique tranche si elle peut ; sinon le radar, qui ne peut que confirmer une culture.

    Calibration zone Sud (ADR-0010) : un radar « non cultivé » contredisait l'optique 3 fois sur 5 en hivernage
    (couvert arboré des petites parcelles) ; il ne déclare donc jamais seul une parcelle non cultivée.
    """
    row = dict(row)
    row["source"] = "optical" if row["cultivated"] is not None else None
    if r is None:
        return row
    row["radar"] = r
    if row["status"] == "uncertain" and r["status"] == "cultivated":
        row.update(cultivated=r["cultivated"], status=r["status"], source="radar")
    elif row["status"] == "uncertain" and r["status"] == "permanent_vegetation":
        row.update(status="permanent_vegetation", source="radar")
    return row


def _fr(x: float, d: int = 2) -> str:
    return f"{x:.{d}f}".replace(".", ",")


def _join(labels: list[str]) -> str:
    labels = [l[0].lower() + l[1:] for l in labels]
    return labels[0] if len(labels) == 1 else ", ".join(labels[:-1]) + " et " + labels[-1]


def _is_hivernage(s: dict) -> bool:
    return s["label"].startswith("Hivernage")


def _peak_text(s: dict | None) -> str:
    if not s or s.get("ndvi_peak") is None:
        return ""
    return f" (pic de NDVI {_fr(s['ndvi_peak'])} le {datetime.fromisoformat(s['ndvi_peak_date']).strftime('%d/%m/%Y')})"


def verdict_of(seasons: list[dict], area_ha: float | None, n_clear: int, n_radar: int | None = None) -> dict:
    """Verdict de la parcelle, fondé sur l'hivernage (ADR-0010).

    La plupart des exploitations de Casamance sont pluviales : une contre-saison sans culture est normale et ne
    rend pas la parcelle « non cultivée ». Règles :
      * au moins une saison cultivée, et toutes les saisons observables non cultivées sont des contre-saisons
        alors qu'un hivernage est cultivé : « cultivée » (culture pluviale) ;
      * toutes les saisons observables cultivées : « cultivée » ;
      * sinon, s'il y a au moins une saison cultivée : « partiellement cultivée » (un hivernage sans culture,
        ou une contre-saison cultivée sans hivernage cultivé observable) ;
      * aucune saison cultivée : « non cultivée » seulement si un hivernage est observé sans culture ;
        sinon « incertaine » (hivernage caché par les nuages ou sous couvert permanent).
    """
    determinate = [s for s in seasons if s["cultivated"] is not None]
    cultivated = [s for s in determinate if s["cultivated"]]
    missed = [s for s in determinate if not s["cultivated"]]
    uncertain = [s for s in seasons if s["cultivated"] is None]
    hiv_cultivated = [s for s in cultivated if _is_hivernage(s)]
    hiv_missed = [s for s in missed if _is_hivernage(s)]
    rainfed = bool(hiv_cultivated) and bool(missed) and not hiv_missed
    if cultivated and (not missed or rainfed):
        verdict = "cultivated"
    elif cultivated:
        verdict = "partially_cultivated"
    elif hiv_missed:
        verdict = "not_cultivated"
    else:
        verdict = "uncertain"
    best = max((s for s in cultivated if s["ndvi_peak"] is not None), key=lambda s: s["ndvi_peak"], default=None)
    peaks = [s["ndvi_peak"] for s in seasons if s["ndvi_peak"] is not None]

    images = f"{n_clear} image{'s' if n_clear > 1 else ''} Sentinel-2 sans nuages"
    by_radar = [s["label"] for s in determinate if s.get("source") == "radar"]
    if n_radar:
        images += f" et {n_radar} passage{'s' if n_radar > 1 else ''} radar Sentinel-1"
    radar_note = ("le radar Sentinel-1 n'a pas pu trancher non plus" if n_radar
                  else "le radar Sentinel-1, qui voit à travers les nuages, n'a pas pu être lu")
    flooded = [s["label"] for s in seasons if (s.get("radar") or {}).get("flooding_date") and s.get("cultivated")]
    hidden = [s["label"] for s in uncertain if s.get("status") == "uncertain"]
    perm = [s["label"] for s in uncertain if s.get("status") == "permanent_vegetation"]
    hidden_note = f" ; {_join(hidden)} non observable (nuages)" if hidden else ""
    labels = lambda xs: _join([s["label"] for s in xs])

    if verdict == "uncertain":
        hiv_perm = [l for l in perm if l.startswith("Hivernage")]
        if hiv_perm:
            summary = (f"Analyse non concluante : couvert végétal permanent sans cycle de culture net en {_join(hiv_perm)}, "
                       "à vérifier sur le terrain (verger, arbres ou végétation naturelle)"
                       + (f" ; pas de culture en {labels(missed)}" if missed else "") + f", d'après {images}.")
        else:
            summary = (f"Analyse incertaine : l'hivernage n'est pas observable ({images} sur les 3 dernières saisons), "
                       f"fréquent en Casamance en saison des pluies ; {radar_note}"
                       + (f" ; pas de culture en {labels(missed)}" if missed else "") + ".")
    elif verdict == "cultivated" and rainfed:
        summary = (f"Parcelle cultivée en {labels(hiv_cultivated)}{_peak_text(best)} : culture pluviale, "
                   f"pas de culture en {labels(missed)}, ce qui est normal sans irrigation, d'après {images}{hidden_note}.")
    elif verdict == "cultivated":
        summary = (f"Parcelle cultivée sur {'les ' + str(len(cultivated)) + ' saisons observables' if uncertain else 'les 3 dernières saisons'}"
                   f"{_peak_text(best)}, d'après {images}{hidden_note}.")
    elif verdict == "not_cultivated":
        summary = (f"Aucun cycle de culture détecté en {labels(hiv_missed)} ni sur les autres saisons observables "
                   f"(NDVI maximal {_fr(max(peaks)) if peaks else '—'}), d'après {images}{hidden_note}.")
    else:
        summary = f"Parcelle cultivée en {labels(cultivated)} mais pas en {labels(missed)}, d'après {images}{hidden_note}."
    if by_radar and verdict != "uncertain":
        summary = summary[:-1] + f" ; {_join(by_radar)} {'tranchée' if len(by_radar) == 1 else 'tranchées'} par le radar (nuages)."
    if flooded:
        summary += f" Mise en eau détectée en {_join(flooded)} : riz de bas-fond probable."
    return {
        "verdict": verdict,
        "seasons_analyzed": len(seasons),
        "cultivated_seasons": len(cultivated),
        "confirmed_area_ha": round(float(area_ha), 4) if area_ha is not None and verdict in ("cultivated", "partially_cultivated") else None,
        "summary": summary,
    }


def analyse(geometry: dict, area_ha: float | None, today: date | None = None, log=print) -> dict:
    today = today or datetime.now(timezone.utc).date()
    seasons = last_seasons(today)
    catalog = pystac_client.Client.open(STAC_URL)
    search = catalog.search(
        collections=[COLLECTION], intersects=geometry,
        datetime=f"{seasons[0].start.isoformat()}/{seasons[-1].end.isoformat()}",
        query={"eo:cloud_cover": {"lt": MAX_TILE_CLOUD}}, max_items=600,
    )
    items = list(search.items())
    chosen = select_items(items, seasons)
    log("scenes", {"catalogue": len(items), "retenues": len(chosen)})

    def read(pair):
        _, it = pair
        try:
            return scene_ndvi(it, geometry)
        except Exception as e:  # une scène illisible n'arrête pas l'analyse
            log("scene.echec", {"item": it.id, "error": str(e)[:200]})
            return None

    with ThreadPoolExecutor(max_workers=READ_THREADS) as pool:
        raw = list(pool.map(read, chosen))
    failures = sum(1 for r in raw if r is None)
    if chosen and failures == len(chosen):
        raise RuntimeError(f"aucune des {len(chosen)} scènes Sentinel-2 n'a pu être lue (réseau ou catalogue)")
    series = [r for r in raw if r is not None]
    series.sort(key=lambda p: p["date"])
    # une seule mesure par date (deux tuiles le même jour)
    by_date: dict[str, dict] = {}
    for p in series:
        cur = by_date.get(p["date"])
        if cur is None or (cur["ndvi"] is None and p["ndvi"] is not None) or (p["ndvi"] is not None and p["cloud_pct"] < cur["cloud_pct"]):
            by_date[p["date"]] = p
    series = [by_date[k] for k in sorted(by_date)]
    season_rows = [classify_season(s, series) for s in seasons]
    n_clear = sum(1 for p in series if p["ndvi"] is not None)

    radar_series: list[dict] | None = None
    if RADAR_ENABLED:
        try:
            s1 = list(catalog.search(collections=[radar.COLLECTION], intersects=geometry,
                                     datetime=f"{seasons[0].start.isoformat()}/{seasons[-1].end.isoformat()}", max_items=600).items())
            passes = radar.select_items(s1, seasons[0].start, seasons[-1].end)
            log("radar.passages", {"catalogue": len(s1), "retenus": len(passes)})
            radar_series = radar.read_series(passes, geometry, log=log)
        except Exception as e:  # noqa: BLE001 — sans radar, l'analyse optique reste valable
            log("radar.indisponible", {"error": str(e)[:300]})
            radar_series = None
    season_rows = [merge_radar(row, radar.classify_season(s.start, s.end, radar_series) if radar_series is not None else None)
                   for row, s in zip(season_rows, seasons)]
    result = verdict_of(season_rows, area_ha, n_clear, len(radar_series) if radar_series else None)
    result.update(seasons=season_rows, ndvi_series=series, radar_series=radar_series or [],
                  provider=PROVIDER_WITH_RADAR if radar_series else PROVIDER)
    return result


def square(lat: float, lng: float, side_m: float = 100.0) -> dict:
    dlat = side_m / 111_320 / 2
    dlng = side_m / (111_320 * math.cos(math.radians(lat))) / 2
    ring = [[lng - dlng, lat + dlat], [lng + dlng, lat + dlat], [lng + dlng, lat - dlat], [lng - dlng, lat - dlat], [lng - dlng, lat + dlat]]
    return {"type": "Polygon", "coordinates": [ring]}


if __name__ == "__main__":   # essai local sans base : python -m sat.retro 12.56 -16.27 [côté_m]
    import json
    import sys
    import time

    lat, lng = float(sys.argv[1]), float(sys.argv[2])
    side = float(sys.argv[3]) if len(sys.argv) > 3 else 100.0
    t0 = time.time()
    res = analyse(square(lat, lng, side), side * side / 10_000, log=lambda e, f: print(e, f, file=sys.stderr))
    res["elapsed_s"] = round(time.time() - t0, 1)
    print(json.dumps(res, ensure_ascii=False, indent=1))
