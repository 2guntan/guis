"""worker-sat (ADR-0005) : analyses rétroactives des parcelles.

Boucle : core.claim_jobs(['retro_analysis'], WORKER_ID, 2) toutes les WORKER_INTERVAL_S secondes
(payload.aggregate_id = parcelle) → watch.start_retro → analyse Sentinel-2 → watch.finish_retro
→ core.complete_job. En cas d'erreur : watch.fail_retro + core.fail_job (rejoué avec délai croissant).
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
from datetime import datetime, timezone

import httpx

from . import retro


def log(event: str, fields: dict | None = None, level: str = "info") -> None:
    print(json.dumps({"at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "level": level, "worker": "worker-sat",
                      "event": event, **(fields or {})}, ensure_ascii=False, default=str), flush=True)


def required(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        log("config.invalide", {"error": f"{name} est requis (voir workers/sat/.env.local.example)"}, "error")
        sys.exit(1)
    return v


class Db:
    """Appels PostgREST en service_role ; le schéma est choisi par l'en-tête Content-Profile."""

    def __init__(self, url: str, key: str):
        self.base = url.rstrip("/") + "/rest/v1"
        self.http = httpx.Client(timeout=60, headers={"apikey": key, "Authorization": f"Bearer {key}",
                                                      "Content-Type": "application/json", "X-Client-Info": "fieldproof-worker-sat"})

    def rpc(self, schema: str, fn: str, args: dict):
        r = self.http.post(f"{self.base}/rpc/{fn}", json=args, headers={"Content-Profile": schema, "Accept-Profile": schema})
        if r.status_code >= 300:
            try:
                msg = r.json().get("message", r.text)
            except ValueError:
                msg = r.text
            raise RuntimeError(f"{schema}.{fn} : {r.status_code} {msg[:500]}")
        return r.json() if r.content else None


class Stop:
    def __init__(self):
        self.event = threading.Event()
        signal.signal(signal.SIGTERM, self._on)
        signal.signal(signal.SIGINT, self._on)

    def _on(self, signum, _frame):
        if not self.event.is_set():
            log("arret.demande", {"signal": signal.Signals(signum).name})
        self.event.set()


def process(db: Db, job: dict) -> None:
    job_id = job["id"]
    parcel = (job.get("payload") or {}).get("aggregate_id")
    t0 = time.time()
    if not parcel:
        db.rpc("core", "fail_job", {"p_job": job_id, "p_error": "payload sans aggregate_id (parcelle)", "p_permanent": True})
        return
    log("travail.debut", {"job": job_id, "parcel_id": parcel, "attempt": job.get("attempts")})
    analysis_id = None
    try:
        start = db.rpc("watch", "start_retro", {"p_parcel": parcel, "p_provider": retro.PROVIDER, "p_job": job_id})
        if start.get("skip"):
            db.rpc("core", "complete_job", {"p_job": job_id, "p_result": {"skipped": True, "reason": start.get("reason")}})
            log("travail.ignore", {"job": job_id, "parcel_id": parcel, "reason": start.get("reason")})
            return
        analysis_id = start["analysis_id"]
        area = float(start["area_ha"]) if start.get("area_ha") is not None else None
        result = retro.analyse(start["geometry"], area, log=lambda e, f: log(e, {"job": job_id, **f}))
        db.rpc("watch", "finish_retro", {"p_analysis": analysis_id, "p_result": result})
        summary = {"analysis_id": analysis_id, "verdict": result["verdict"], "cultivated_seasons": result["cultivated_seasons"],
                   "seasons_analyzed": result["seasons_analyzed"], "clear_scenes": sum(1 for p in result["ndvi_series"] if p["ndvi"] is not None)}
        db.rpc("core", "complete_job", {"p_job": job_id, "p_result": summary})
        log("travail.termine", {"job": job_id, "parcel_id": parcel, "s": round(time.time() - t0, 1), **summary})
    except Exception as e:  # noqa: BLE001 — tout échec est journalisé et rejoué
        msg = str(e)[:1500]
        if analysis_id:
            try:
                db.rpc("watch", "fail_retro", {"p_analysis": analysis_id, "p_error": msg})
            except Exception as e2:  # noqa: BLE001
                log("fail_retro.echec", {"job": job_id, "error": str(e2)[:300]}, "error")
        try:
            status = db.rpc("core", "fail_job", {"p_job": job_id, "p_error": msg, "p_permanent": False})
        except Exception as e3:  # noqa: BLE001
            status = f"non enregistré : {e3}"
        log("travail.echec", {"job": job_id, "parcel_id": parcel, "status": status, "error": msg}, "error")


def main() -> None:
    db = Db(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"))
    worker_id = os.environ.get("WORKER_ID", "").strip() or f"worker-sat-{os.getpid()}"
    interval = float(os.environ.get("WORKER_INTERVAL_S", "5"))
    batch = int(os.environ.get("WORKER_BATCH_SIZE", "2"))
    once = "--once" in sys.argv
    stop = Stop()
    log("demarrage", {"worker_id": worker_id, "interval_s": interval, "batch": batch, "stac": retro.STAC_URL, "once": once})
    failures = 0
    while not stop.event.is_set():
        try:
            jobs = db.rpc("core", "claim_jobs", {"p_kinds": ["retro_analysis"], "p_worker": worker_id, "p_limit": batch}) or []
            failures = 0
            for job in jobs:
                process(db, job)
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
        stop.event.wait(interval)
    log("arret.termine")


if __name__ == "__main__":
    main()
