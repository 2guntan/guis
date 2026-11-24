"""Statut et alertes d'un champ de pomme de terre à partir de sa série NDVI (NOTE-CADRAGE.md §4).

Fonction pure, sans réseau ni base : `field_status(sown_on, series, today, area_ha, buffered)`.
La pomme de terre se cultive en contre-saison froide irriguée : sol nu au semis, levée vers J+20 à J+30,
pic vers J+50 à J+70, sénescence ensuite, récolte vers J+90 à J+110.

Les seuils sont des constantes du module : on les recalibrera sur les premiers champs suivis.
"""

from __future__ import annotations

from datetime import date, timedelta

BARE_MAX = 0.25          # au-dessous : sol nu (ou culture pas encore levée)
GROWTH_MIN = 0.45        # au-dessus : couvert bien installé
PEAK_MARGIN = 0.05       # à moins de 0,05 du maximum observé : pic
PEAK_MIN_DAY = 40        # pas de pic avant J+40
SENESCENCE_DROP = 0.10   # baisse sous le pic qui signe la sénescence
EMERGENCE_DEADLINE = 35  # pas de levée à J+35 : alerte
DROP_ALERT = 0.15        # chute entre deux images claires consécutives : alerte
DROP_ALERT_UNTIL = 80    # … hors fin de cycle (avant J+80)
GREEN_AT_SOWING = 0.40   # déjà vert au semis : alerte
SOWING_WINDOW = 10       # image « au semis » : à ±10 jours
LOOKBACK = 15            # la série commence 15 jours avant le semis
INDICATIVE_HA = 0.1      # au-dessous : suivi indicatif (trop peu de pixels Sentinel-2)

STATUSES = ("waiting", "bare", "emergence", "growth", "peak", "senescence")


def _fr(x: float) -> str:
    return f"{x:.2f}".replace(".", ",")


def _d(v) -> date:
    return v if isinstance(v, date) else date.fromisoformat(str(v)[:10])


def field_status(sown_on: date | str | None, series: list[dict], today: date, area_ha: float | None = None,
                 buffered: bool = True) -> dict:
    """`series` : [{date, ndvi (None si nuageux), …}]. Renvoie statut, jours depuis le semis, dernier NDVI, pic,
    suivi indicatif et alertes [{code, message}]."""
    sown = _d(sown_on) if sown_on else None
    clear = sorted(({"date": _d(p["date"]), "ndvi": float(p["ndvi"])} for p in series if p.get("ndvi") is not None),
                   key=lambda p: p["date"])
    if sown:
        clear = [p for p in clear if p["date"] >= sown - timedelta(days=LOOKBACK)]
    days = (today - sown).days if sown else None
    after = [p for p in clear if not sown or p["date"] >= sown]
    indicative = (area_ha is not None and area_ha < INDICATIVE_HA) or not buffered

    out = {
        "status": "waiting",
        "days_since_sowing": days,
        "last_ndvi": round(after[-1]["ndvi"], 4) if after else None,
        "last_scene_date": after[-1]["date"].isoformat() if after else None,
        "peak_ndvi": round(max(p["ndvi"] for p in after), 4) if after else None,
        "indicative": indicative,
        "alerts": [],
    }

    def day_of(p) -> int | None:
        return (p["date"] - sown).days if sown else None

    # Alerte : déjà vert au semis (image claire la plus proche du semis, à ±10 jours).
    if sown:
        near = [p for p in clear if abs((p["date"] - sown).days) <= SOWING_WINDOW]
        if near:
            p = min(near, key=lambda p: abs((p["date"] - sown).days))
            if p["ndvi"] > GREEN_AT_SOWING:
                out["alerts"].append({"code": "green_at_sowing",
                                      "message": f"Champ déjà vert au semis (NDVI {_fr(p['ndvi'])} le {p['date'].strftime('%d/%m/%Y')}) : "
                                                 "date de semis ou contour à vérifier"})

    if not after:
        return out

    last = after[-1]["ndvi"]
    peak_p = max(after, key=lambda p: p["ndvi"])
    peak = peak_p["ndvi"]
    rising = len(after) >= 2 and last > after[-2]["ndvi"]
    # Encore en nette montée (plus que la marge du pic depuis l'image précédente) : pas encore le pic.
    still_rising = len(after) >= 2 and last - after[-2]["ndvi"] >= PEAK_MARGIN

    if peak >= GROWTH_MIN and after[-1]["date"] > peak_p["date"] and last <= peak - SENESCENCE_DROP:
        status = "senescence"
    # Sans date de semis, un pic se reconnaît à un plateau (deux images claires près du maximum).
    elif peak >= GROWTH_MIN and last >= peak - PEAK_MARGIN and not still_rising and (
            days >= PEAK_MIN_DAY if days is not None else len(after) >= 2 and after[-2]["ndvi"] >= peak - PEAK_MARGIN):
        status = "peak"
    elif last >= GROWTH_MIN or (days is not None and days >= 30 and last >= BARE_MAX and rising):
        status = "growth"
    elif last >= BARE_MAX:
        status = "emergence"
    else:
        status = "bare"
    out["status"] = status

    # Alerte : pas de levée à J+35.
    if days is not None and days >= EMERGENCE_DEADLINE and peak < BARE_MAX:
        out["alerts"].append({"code": "no_emergence",
                              "message": f"Pas de levée à J+{days} (NDVI maximal {_fr(peak)}) : semis non fait, échec ou mauvais contour"})

    # Alerte : chute de NDVI entre deux images claires consécutives, hors fin de cycle.
    for a, b in zip(after, after[1:]):
        drop = a["ndvi"] - b["ndvi"]
        db = day_of(b)
        if drop > DROP_ALERT and (db is None or db < DROP_ALERT_UNTIL):
            out["alerts"].append({"code": "ndvi_drop",
                                  "message": f"Chute de NDVI de {_fr(drop)} entre le {a['date'].strftime('%d/%m')} et le "
                                             f"{b['date'].strftime('%d/%m/%Y')} : stress hydrique ou maladie, à vérifier"})
            break
    return out
