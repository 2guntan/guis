"""Le worker contre une vraie base PostGIS (DATABASE_URL), avec des scènes simulées : réclamer un travail,
écrire la série et le statut, terminer ou échouer le travail, enfiler le recalcul quotidien."""

import os
import uuid
from datetime import date, datetime, timedelta, timezone

import psycopg
import pytest
from psycopg.rows import dict_row

from sat import main

URL = os.environ.get("DATABASE_URL")
pytestmark = pytest.mark.skipif(not URL, reason="DATABASE_URL absent : test du worker contre PostGIS ignoré")

SOWN = date(2026, 11, 1)
TODAY = SOWN + timedelta(days=40)


class Item:
    def __init__(self, d):
        self.id = f"S2_{d}"
        self.d = d


@pytest.fixture()
def conn():
    with psycopg.connect(URL, autocommit=True, row_factory=dict_row) as c:
        c.execute("truncate users, sessions, producers, seed_distributions, fields, ndvi_points, field_status, jobs, worker_state restart identity cascade")
        yield c


def add_field(conn, sown=SOWN, side=0.001):
    pid, fid = uuid.uuid4(), uuid.uuid4()
    conn.execute("insert into producers (id, last_name, first_name, consent_at) values (%s, 'Diop', 'Awa', now())", (pid,))
    conn.execute(
        """insert into fields (id, producer_id, sown_on, geom) values (%s, %s, %s,
           st_setsrid(st_makeenvelope(-16.95, 15.05, -16.95 + %s, 15.05 + %s), 4326))""", (fid, pid, sown, side, side))
    return fid


def fake(ndvi_by_day):
    def find(_g, start, end):
        return [Item(SOWN + timedelta(days=d)) for d in ndvi_by_day if start <= SOWN + timedelta(days=d) <= end]

    def read(item, _g):
        v = ndvi_by_day[(item.d - SOWN).days]
        if v == "panne":
            raise OSError("lecture COG impossible")
        return {"date": item.d.isoformat(), "ndvi": v, "cloud_pct": 0 if v is not None else 100, "pixels": 100, "buffered": True,
                "scene_id": item.id}
    return find, read


def test_un_nouveau_contour_est_calcule_et_le_travail_termine(conn):
    fid = add_field(conn)
    job = conn.execute("select * from claim_jobs('test', 5)").fetchone()
    assert job["field_id"] == fid
    find, read = fake({-5: 0.12, 5: 0.13, 20: None, 25: 0.31, 38: 0.55})
    main.run_job(conn, job, today=TODAY, find=find, read=read)
    pts = conn.execute("select scene_date, ndvi from ndvi_points where field_id = %s order by scene_date", (fid,)).fetchall()
    assert len(pts) == 5
    st = conn.execute("select * from field_status where field_id = %s", (fid,)).fetchone()
    assert (st["status"], st["days_since_sowing"], st["last_ndvi"], st["indicative"]) == ("growth", 40, pytest.approx(0.55), False)
    j = conn.execute("select status, result from jobs where id = %s", (job["id"],)).fetchone()
    assert j["status"] == "done"
    assert j["result"]["new_scenes"] == 5


def test_les_scenes_deja_mesurees_ne_sont_pas_relues(conn):
    fid = add_field(conn)
    find, read = fake({5: 0.13, 25: 0.31})
    main.run_job(conn, conn.execute("select * from claim_jobs('test', 5)").fetchone(), today=TODAY, find=find, read=read)
    conn.execute("select enqueue_field(%s)", (fid,))
    seen = []
    find2, _ = fake({5: 0.13, 25: 0.31, 35: 0.5})

    def find_skip(g, a, b):
        skip = {r["d"] for r in conn.execute("select scene_date::text as d from ndvi_points where field_id = %s", (fid,))}
        return [it for it in find2(g, a, b) if it.d.isoformat() not in skip]

    def read2(item, g):
        seen.append(item.d)
        return read(item, g) if (item.d - SOWN).days != 35 else {**read(Item(SOWN + timedelta(days=25)), g), "date": item.d.isoformat(), "ndvi": 0.5}
    main.run_job(conn, conn.execute("select * from claim_jobs('test', 5)").fetchone(), today=TODAY, find=find_skip, read=read2)
    assert seen == [SOWN + timedelta(days=35)]
    assert conn.execute("select count(*) as n from ndvi_points").fetchone()["n"] == 3


def test_toutes_les_scenes_illisibles_le_travail_est_rejoue(conn):
    add_field(conn)
    job = conn.execute("select * from claim_jobs('test', 5)").fetchone()
    find, read = fake({5: "panne", 10: "panne"})
    main.run_job(conn, job, today=TODAY, find=find, read=read)
    j = conn.execute("select status, last_error, run_after > now() as later from jobs where id = %s", (job["id"],)).fetchone()
    assert j["status"] == "queued"
    assert "aucune des 2 scènes" in j["last_error"]
    assert j["later"], "rejoué avec un délai"


def test_une_scene_illisible_n_arrete_pas_le_calcul(conn):
    add_field(conn)
    job = conn.execute("select * from claim_jobs('test', 5)").fetchone()
    find, read = fake({5: "panne", 10: 0.14})
    main.run_job(conn, job, today=TODAY, find=find, read=read)
    assert conn.execute("select status from jobs where id = %s", (job["id"],)).fetchone()["status"] == "done"


def test_un_nouveau_contour_efface_les_anciennes_mesures(conn):
    fid = add_field(conn)
    find, read = fake({5: 0.13})
    main.run_job(conn, conn.execute("select * from claim_jobs('test', 5)").fetchone(), today=TODAY, find=find, read=read)
    conn.execute("update fields set geom = st_setsrid(st_makeenvelope(-16.95, 15.05, -16.948, 15.052), 4326) where id = %s", (fid,))
    assert conn.execute("select count(*) as n from ndvi_points").fetchone()["n"] == 0
    assert conn.execute("select count(*) as n from jobs where status = 'queued'").fetchone()["n"] == 1


def test_petit_champ_suivi_indicatif(conn):
    add_field(conn, side=0.0002)   # ≈ 22 m de côté, 0,05 ha
    find, read = fake({5: 0.13})
    main.run_job(conn, conn.execute("select * from claim_jobs('test', 5)").fetchone(), today=TODAY, find=find, read=read)
    assert conn.execute("select indicative from field_status").fetchone()["indicative"] is True


def test_enfilement_quotidien_une_fois_par_jour(conn):
    add_field(conn)
    add_field(conn)
    conn.execute("update jobs set status = 'done'")
    morning = datetime(2026, 11, 24, 5, tzinfo=timezone.utc)
    assert main.daily(conn, datetime(2026, 11, 24, 2, tzinfo=timezone.utc)) is None, "pas avant l'heure prévue"
    assert main.daily(conn, morning) == 2
    assert main.daily(conn, morning + timedelta(hours=3)) is None, "une seule fois par jour"
    assert main.daily(conn, morning + timedelta(days=1)) == 0, "déjà en attente : rien de plus"
