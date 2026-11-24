from datetime import date, timedelta

from sat.status import field_status

SOWN = date(2026, 11, 15)


def serie(*pairs):
    """(jour depuis le semis, NDVI ou None)."""
    return [{"date": (SOWN + timedelta(days=d)).isoformat(), "ndvi": v} for d, v in pairs]


def st(pairs, day, **kw):
    return field_status(SOWN, serie(*pairs), SOWN + timedelta(days=day), **kw)


def codes(r):
    return [a["code"] for a in r["alerts"]]


def test_sans_image_claire_en_attente():
    r = st([(3, None), (8, None)], 10, area_ha=1.0)
    assert r["status"] == "waiting"
    assert r["last_ndvi"] is None
    assert r["days_since_sowing"] == 10
    assert codes(r) == []


def test_serie_vide():
    assert field_status(SOWN, [], SOWN, area_ha=1.0)["status"] == "waiting"


def test_seme_sol_nu():
    r = st([(-5, 0.12), (5, 0.13), (10, 0.14)], 12, area_ha=1.0)
    assert r["status"] == "bare"
    assert codes(r) == []


def test_levee():
    assert st([(5, 0.13), (15, 0.18), (24, 0.29)], 25, area_ha=1.0)["status"] == "emergence"


def test_en_croissance():
    assert st([(5, 0.13), (24, 0.29), (35, 0.52)], 36, area_ha=1.0)["status"] == "growth"
    # Après J+30, une montée au-dessus de 0,25 compte déjà comme croissance.
    assert st([(5, 0.13), (24, 0.27), (32, 0.36)], 33, area_ha=1.0)["status"] == "growth"


def test_pic():
    r = st([(5, 0.13), (24, 0.29), (35, 0.52), (45, 0.71), (55, 0.73), (60, 0.72)], 61, area_ha=1.0)
    assert r["status"] == "peak"
    assert r["peak_ndvi"] == 0.73
    assert r["last_ndvi"] == 0.72


def test_encore_en_montee_apres_j40_pas_encore_le_pic():
    assert st([(5, 0.13), (25, 0.31), (42, 0.55)], 43, area_ha=1.0)["status"] == "growth"


def test_pas_de_pic_avant_j40():
    assert st([(5, 0.13), (25, 0.4), (35, 0.6)], 36, area_ha=1.0)["status"] == "growth"


def test_senescence():
    r = st([(5, 0.13), (35, 0.52), (55, 0.75), (80, 0.6), (95, 0.4)], 96, area_ha=1.0)
    assert r["status"] == "senescence"
    assert codes(r) == [], "baisse progressive de fin de cycle, pas d'alerte"


def test_alerte_pas_de_levee_a_j35():
    r = st([(5, 0.12), (20, 0.14), (34, 0.16)], 36, area_ha=1.0)
    assert r["status"] == "bare"
    assert codes(r) == ["no_emergence"]
    assert "J+36" in r["alerts"][0]["message"]


def test_pas_d_alerte_de_levee_avant_j35():
    assert codes(st([(5, 0.12), (20, 0.14)], 30, area_ha=1.0)) == []


def test_alerte_chute_de_ndvi_hors_fin_de_cycle():
    r = st([(5, 0.13), (35, 0.55), (45, 0.68), (50, 0.48)], 51, area_ha=1.0)
    assert "ndvi_drop" in codes(r)
    assert "0,20" in next(a for a in r["alerts"] if a["code"] == "ndvi_drop")["message"]


def test_chute_en_fin_de_cycle_sans_alerte():
    assert "ndvi_drop" not in codes(st([(5, 0.13), (60, 0.75), (85, 0.55)], 86, area_ha=1.0))


def test_les_images_nuageuses_ne_comptent_pas_comme_chute():
    assert codes(st([(5, 0.13), (35, 0.55), (40, None), (45, 0.6)], 46, area_ha=1.0)) == []


def test_alerte_deja_vert_au_semis():
    r = st([(-8, 0.62), (4, 0.58)], 6, area_ha=1.0)
    assert "green_at_sowing" in codes(r)


def test_image_trop_ancienne_ignoree():
    # 20 jours avant le semis : hors de la fenêtre (semis moins 15 jours) et hors des ±10 jours.
    r = st([(-20, 0.7), (5, 0.12)], 6, area_ha=1.0)
    assert codes(r) == []
    assert r["status"] == "bare"


def test_suivi_indicatif():
    assert st([(5, 0.13)], 6, area_ha=0.05)["indicative"] is True
    assert st([(5, 0.13)], 6, area_ha=1.0)["indicative"] is False
    assert st([(5, 0.13)], 6, area_ha=1.0, buffered=False)["indicative"] is True, "marge de 5 m abandonnée"


def test_sans_date_de_semis():
    r = field_status(None, serie((5, 0.13), (35, 0.55)), SOWN + timedelta(days=40), area_ha=1.0)
    assert r["status"] == "growth"
    assert r["days_since_sowing"] is None
    assert codes(r) == []
