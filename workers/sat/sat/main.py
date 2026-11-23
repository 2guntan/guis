"""worker-sat Guis : suivi NDVI Sentinel-2 des champs depuis leur semis.

Boucle reprise de Fieldproof (workers/sat/sat/main.py) : claim_jobs → traitement → complete_job, ou fail_job
(rejoué avec un délai croissant). Différences : accès direct à PostgreSQL (psycopg) au lieu de PostgREST,
un travail = un champ, et un enfilement quotidien de tous les champs (une fois par jour, après DAILY_HOUR_UTC).
Arrêt propre sur SIGTERM : le travail en cours se termine, rien de nouveau n'est réclamé.

    python -m sat.main [--once]
"""

from __future__ import annotations

import json
import os
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from . import scenes
from .status import LOOKBACK, field_status

READ_THREADS = int(os.environ.get("SAT_READ_THREADS", "4"))
DAILY_HOUR_UTC = int(os.environ.get("SAT_DAILY_HOUR_UTC", "4"))
NO_SOWING_WINDOW_DAYS = 120   # champ sans date de semis : les 120 derniers jours


def log(event: str, fields: dict | None = None, level: str = "info") -> None:
    print(json.dumps({"at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "level": level, "worker": "worker-sat",
                      "event": event, **(fields or {})}, ensure_ascii=False, default=str), flush=True)


class Stop:
    def __init__(self):
        self.event = threading.Event()
        signal.signal(signal.SIGTERM, self._on)
        signal.signal(signal.SIGINT, self._on)

    def _on(self, signum, _frame):
        if not self.event.is_set():
            log("arret.demande", {"signal": signal.Signals(signum).name})
        self.event.set()


def process(conn: psycopg.Connection, job: dict, today: date | None = None, read=scenes.scene_ndvi, find=None) -> dict:
    """Calcule la série et le statut d'un champ. `read` et `find` se remplacent dans les tests."""
    today = today or datetime.now(timezone.utc).date()
    find = find or (lambda g, a, b: scenes.select_items(scenes.search(g, a, b), skip))
    f = conn.execute(
        """select id, st_asgeojson(geom)::jsonb as geometry, sown_on, area_measured_ha::float8 as area_ha
             from fields where id = %s""", (job["field_id"],)).fetchone()
    if not f or f["geometry"] is None:
        return {"skipped": True, "reason": "champ sans contour"}
    start = (f["sown_on"] - timedelta(days=LOOKBACK)) if f["sown_on"] else today - timedelta(days=NO_SOWING_WINDOW_DAYS)
    skip = {r["d"] for r in conn.execute("select scene_date::text as d from ndvi_points where field_id = %s", (f["id"],))}
    items = find(f["geometry"], start, today)

    def safe_read(it):
        try:
            return read(it, f["geometry"])
        except Exception as e:  # noqa: BLE001 — une scène illisible n'arrête pas le calcul
            log("scene.echec", {"field_id": str(f["id"]), "item": getattr(it, "id", "?"), "error": str(e)[:200]}, "warning")
            return "échec"

    with ThreadPoolExecutor(max_workers=READ_THREADS) as pool:
        raw = list(pool.map(safe_read, items))
    failures = sum(1 for r in raw if r == "échec")
    if items and failures == len(items):
        raise RuntimeError(f"aucune des {len(items)} scènes Sentinel-2 n'a pu être lue (réseau ou catalogue)")
    for p in (r for r in raw if isinstance(r, dict)):
        conn.execute(
            """insert into ndvi_points (field_id, scene_date, ndvi, cloud_pct, pixels, scene_id, buffered) values (%s, %s, %s, %s, %s, %s, %s)
               on conflict (field_id, scene_date) do update set ndvi = excluded.ndvi, cloud_pct = excluded.cloud_pct,
                 pixels = excluded.pixels, scene_id = excluded.scene_id, buffered = excluded.buffered""",
            (f["id"], p["date"], p["ndvi"], p["cloud_pct"], p["pixels"], p["scene_id"], p["buffered"]))

    series = conn.execute(
        "select scene_date as date, ndvi, pixels, buffered from ndvi_points where field_id = %s and scene_date >= %s order by scene_date",
        (f["id"], start)).fetchall()
    clear = [p for p in series if p["ndvi"] is not None]
    buffered = all(p["buffered"] for p in clear) if clear else True
    st = field_status(f["sown_on"], series, today, f["area_ha"], buffered)
    conn.execute(
        """insert into field_status (field_id, status, days_since_sowing, last_ndvi, last_scene_date, peak_ndvi, indicative, pixels, alerts, computed_at)
           values (%s, %s, %s, %s, %s, %s, %s, %s, %s, now())
           on conflict (field_id) do update set status = excluded.status, days_since_sowing = excluded.days_since_sowing,
             last_ndvi = excluded.last_ndvi, last_scene_date = excluded.last_scene_date, peak_ndvi = excluded.peak_ndvi,
             indicative = excluded.indicative, pixels = excluded.pixels, alerts = excluded.alerts, computed_at = now()""",
        (f["id"], st["status"], st["days_since_sowing"], st["last_ndvi"], st["last_scene_date"], st["peak_ndvi"], st["indicative"],
         clear[-1]["pixels"] if clear else None, Jsonb(st["alerts"])))
    return {"status": st["status"], "new_scenes": len(items), "clear_scenes": len(clear), "alerts": [a["code"] for a in st["alerts"]]}


def daily(conn: psycopg.Connection, now: datetime | None = None) -> int | None:
    """Une fois par jour (après DAILY_HOUR_UTC), enfile le recalcul de tous les champs relevés."""
    now = now or datetime.now(timezone.utc)
    if now.hour < DAILY_HOUR_UTC:
        return None
    today = now.date().isoformat()
    row = conn.execute("select value from worker_state where key = 'daily'").fetchone()
    if row and row["value"] == today:
        return None
    n = conn.execute("select enqueue_all_fields() as n").fetchone()["n"]
    conn.execute("""insert into worker_state (key, value) values ('daily', %s)
                    on conflict (key) do update set value = excluded.value, updated_at = now()""", (today,))
    log("quotidien.enfile", {"champs": n})
    return n


def run_job(conn: psycopg.Connection, job: dict, **kw) -> None:
    t0 = time.time()
    try:
        with conn.transaction():
            result = process(conn, job, **kw)
            conn.execute("select complete_job(%s, %s)", (job["id"], Jsonb(result)))
        log("travail.termine", {"job": job["id"], "field_id": str(job["field_id"]), "s": round(time.time() - t0, 1), **result})
    except Exception as e:  # noqa: BLE001 — tout échec est journalisé et rejoué
        msg = str(e)[:1500]
        status = conn.execute("select fail_job(%s, %s) as s", (job["id"], msg)).fetchone()["s"]
        log("travail.echec", {"job": job["id"], "field_id": str(job["field_id"]), "status": status, "error": msg}, "error")


def main() -> None:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        log("config.invalide", {"error": "DATABASE_URL est requis"}, "error")
        sys.exit(1)
    worker_id = os.environ.get("WORKER_ID", "").strip() or f"worker-sat-{os.getpid()}"
    interval = float(os.environ.get("WORKER_INTERVAL_S", "10"))
    once = "--once" in sys.argv
    stop = Stop()
    log("demarrage", {"worker_id": worker_id, "interval_s": interval, "stac": scenes.STAC_URL, "once": once})
    failures = 0
    while not stop.event.is_set():
        try:
            with psycopg.connect(url, autocommit=True, row_factory=dict_row) as conn:
                daily(conn)
                jobs = conn.execute("select * from claim_jobs(%s, %s)", (worker_id, 2)).fetchall()
                failures = 0
                for job in jobs:
                    run_job(conn, job)
                    if stop.event.is_set():
                        break
        except Exception as e:  # noqa: BLE001 — incident passager : on recule puis on reprend
            failures += 1
            wait = min(interval * 2 ** min(failures - 1, 6), 300)
            log("iteration.echec", {"error": str(e)[:500], "retry_in_s": wait}, "error")
            stop.event.wait(wait)
            continue
        if once:
            break
        stop.event.wait(interval if not jobs else 0.1)
    log("arret.termine")


if __name__ == "__main__":
    main()
