"""Energy engine (app.core.energy): climate data, physics, classification, API."""
import math

import pytest

from app.core.energy import BuildingInputs, climate, compute
from app.core.energy import engine

API = "/api/v1"

OLD_FLAT = dict(comune="Milano", tipologia="appartamento", anno_costruzione=1965,
                piano="intermedio", telaio="Legno", vetro="Singolo",
                generatore="caldaia_tradizionale", anno_generatore=1995)


def _ep(**kw):
    sqm = kw.pop("square_meters", 80)
    return compute(BuildingInputs(**kw), square_meters=sqm, with_improvements=False)


class TestClimate:
    @pytest.mark.parametrize("name, prov, zone, gg", [
        ("Milano", None, "E", 2404), ("Roma", None, "D", 1415), ("Napoli", None, "C", 1034),
        ("Palermo", None, "B", 751), ("Torino", None, "E", 2617), ("Monza", None, "E", 2404),
        ("Andria", None, "C", 1377), ("Sestriere", None, "F", 5165),
        ("Lampedusa e Linosa", None, "A", 568), ("agliè", "TO", "E", 2617),
    ])
    def test_dpr_412_values(self, name, prov, zone, gg):
        c = climate.find(name, prov)
        assert c is not None and (c.zona, c.gradi_giorno) == (zone, gg)

    def test_table_covers_italy(self):
        rows, _ = climate._table()
        assert len(rows) > 7800
        assert {r.zona for r in rows} == set("ABCDEF")

    def test_search_prefix_first(self):
        names = [c.nome for c in climate.search("mila")]
        assert names[0] == "Milano"

    def test_resolve_prefers_nearest_named_part(self):
        c = climate.resolve("Via Roma 1, Moncalieri, Torino, Piemonte, 10024, Italia", 45.0, 7.68)
        assert c.nome == "Moncalieri"

    def test_resolve_by_coordinates_only(self):
        assert climate.resolve(None, 45.4643, 9.1895).nome == "Milano"
        assert climate.resolve("Nowhere", 0.0, 0.0) is None

    @pytest.mark.parametrize("zone, gg", [("E", 2404), ("B", 751), ("F", 4000)])
    def test_monthly_profile_reproduces_gg(self, zone, gg):
        temps = engine.monthly_temperatures(zone, gg)
        total = sum(d * (20 - t) for d, t in zip(engine.SEASON_DAYS[zone], temps))
        assert total == pytest.approx(gg)
        assert sum(engine.SEASON_DAYS[zone]) == climate.HEATING_DAYS[zone]


class TestClassification:
    @pytest.mark.parametrize("ratio, letter", [
        (0.0, "A4"), (0.40, "A4"), (0.41, "A3"), (0.8, "A2"), (1.0, "A1"), (1.2, "B"),
        (1.5, "C"), (2.0, "D"), (2.6, "E"), (3.5, "F"), (3.51, "G"), (9.0, "G"),
    ])
    def test_dm_2015_thresholds(self, ratio, letter):
        assert engine._class_for_ratio(ratio) == letter

    @pytest.mark.parametrize("ratio", [0.0, 0.2, 0.4, 0.55, 0.99, 1.1, 1.49, 1.9, 2.5, 3.0, 3.5, 4.2, 8.0])
    def test_score_matches_class_on_gauge(self, ratio):
        # client gauge: index = round(score / 100 * 9), counted from G
        score = engine.score_for_ratio(ratio)
        index = math.floor(score / 100 * 9 + 0.5)
        assert engine.ENERGY_CLASS_LETTERS[9 - index] == engine._class_for_ratio(ratio)

    def test_window_u_values(self):
        assert engine.window_u("Legno", "Doppio") == pytest.approx(2.825)
        assert engine.window_u("Alluminio", "Singolo") == pytest.approx(6.025)

    def test_dhw_need_uni_ts_11300_2(self):
        litres = 1.067 * 80 + 36.67
        assert engine.dhw_need(80) == pytest.approx(1.162 * litres * 25 * 365 / 1000)
        assert engine.dhw_need(20) == pytest.approx(1.162 * 50 * 25 * 365 / 1000)


class TestPhysics:
    def test_old_flat_in_milan_is_poor(self):
        r = _ep(**OLD_FLAT)
        assert r["classe"] in ("E", "F", "G")
        assert r["clima"]["zona"] == "E"
        assert r["ep"]["gl_nren"] > r["riferimento"]["gl_nren_rif_standard"] * 2

    def test_new_heat_pump_house_is_excellent(self):
        r = _ep(comune="Bolzano", tipologia="villetta", anno_costruzione=2021, numero_piani=2,
                telaio="PVC", vetro="Triplo", generatore="pompa_calore_aria_acqua",
                terminali="pavimento", anno_generatore=2021, fotovoltaico_kwp=6,
                regolazione="climatica_valvole", square_meters=140)
        assert r["classe"] in ("A4", "A3", "A2")
        assert r["qualita_involucro_invernale"] in ("alta", "media")

    @pytest.mark.parametrize("change", [
        {"isolamento_pareti_cm": 12}, {"vetro": "Triplo", "telaio": "PVC"},
        {"generatore": "caldaia_condensazione"}, {"generatore": "pompa_calore_aria_acqua"},
        {"regolazione": "climatica_valvole"}, {"solare_termico": True},
    ])
    def test_each_improvement_lowers_ep(self, change):
        base = _ep(**OLD_FLAT)["ep"]["gl_nren"]
        assert _ep(**{**OLD_FLAT, **change})["ep"]["gl_nren"] < base

    def test_top_floor_and_colder_climate_need_more(self):
        mid = _ep(**OLD_FLAT)["ep"]["h_nd"]
        top = _ep(**{**OLD_FLAT, "piano": "ultimo"})["ep"]["h_nd"]
        cold = _ep(**{**OLD_FLAT, "comune": "Sestriere"})["ep"]["h_nd"]
        warm = _ep(**{**OLD_FLAT, "comune": "Palermo"})["ep"]["h_nd"]
        assert warm < mid < top and mid < cold

    def test_pv_offsets_only_electric_uses(self):
        gas = {**OLD_FLAT, "piano": "ultimo"}
        assert _ep(**gas, fotovoltaico_kwp=3)["ep"]["gl_nren"] >= _ep(**gas)["ep"]["gl_nren"] - 25
        hp = {**gas, "generatore": "pompa_calore_aria_acqua"}
        assert _ep(**hp, fotovoltaico_kwp=3)["ep"]["gl_nren"] < _ep(**hp)["ep"]["gl_nren"]

    def test_assumptions_reported_and_shrink(self):
        empty = compute(BuildingInputs(), with_improvements=False)
        fields = {a["campo"] for a in empty["assunzioni"]}
        assert {"square_meters", "comune", "anno_costruzione", "generatore"} <= fields
        full = compute(BuildingInputs(
            comune="Roma", tipologia="appartamento", anno_costruzione=1980, piano="intermedio",
            lati_esposti=2, orientamento="sud", muratura="mattoni_forati", spessore_muri="30-40cm",
            isolamento_pareti_cm=0, telaio="Legno", vetro="Doppio", superficie_finestrata=12,
            generatore="caldaia_condensazione", combustibile="metano", anno_generatore=2015,
            terminali="radiatori", regolazione="valvole_termostatiche", acs="combinata",
            raffrescamento="split"), square_meters=90, avg_height=2.8, with_improvements=False)
        assert full["assunzioni"] == []
        assert full["ep"]["c_nren"] > 0

    def test_improvements_ranked_with_global_scenario(self):
        r = compute(BuildingInputs(**{**OLD_FLAT, "piano": "ultimo"}), square_meters=80)
        items = r["interventi"]
        assert items and items[-1]["codice"] == "riqualificazione_globale"
        singles = items[:-1]
        assert [i["riduzione_ep_pct"] for i in singles] == sorted(
            (i["riduzione_ep_pct"] for i in singles), reverse=True)
        assert all(i["riduzione_ep_pct"] > 0 and i["investimento_eur"] > 0 for i in items)
        assert items[-1]["classi_guadagnate"] >= max(i["classi_guadagnate"] for i in singles)

    def test_legacy_flat_columns_still_count(self):
        legacy = compute(BuildingInputs(), legacy={"heating_type": "Pompa di Calore"},
                         with_improvements=False)
        assert legacy["impianto"]["generatore"] == "Pompa di calore aria-acqua"


class TestEnergyApi:
    def test_estimate_requires_auth(self, client):
        assert client.post(f"{API}/estimate", json={}).status_code == 401

    def test_estimate(self, client, auth_a):
        headers, _ = auth_a
        r = client.post(f"{API}/estimate", headers=headers,
                        json={"square_meters": 80, "building": OLD_FLAT})
        assert r.status_code == 200
        body = r.json()
        assert body["classe"] in engine.ENERGY_CLASS_LETTERS
        assert body["clima"]["comune"]["comune"] == "Milano"
        assert body["interventi"]

    @pytest.mark.parametrize("payload", [
        {"building": {"generatore": "reattore"}},
        {"building": {"pippo": 1}},
        {"energy_score": 3},
    ])
    def test_estimate_validation(self, client, auth_a, payload):
        headers, _ = auth_a
        assert client.post(f"{API}/estimate", headers=headers, json=payload).status_code == 422

    def test_comuni_search_and_resolve(self, client, auth_a):
        headers, _ = auth_a
        found = client.get(f"{API}/climate/comuni", params={"q": "napo"}, headers=headers).json()
        assert found[0]["comune"] == "Napoli" and found[0]["zona"] == "C"
        hit = client.get(f"{API}/climate/resolve", headers=headers,
                         params={"address": "Piazza del Plebiscito, Napoli, Campania, Italia"})
        assert hit.status_code == 200 and hit.json()["gradi_giorno"] == 1034
        miss = client.get(f"{API}/climate/resolve", params={"address": "x"}, headers=headers)
        assert miss.status_code == 404

    def test_survey_list_shows_comune(self, client, auth_a):
        headers, _ = auth_a
        client.post(f"{API}/surveys", headers=headers,
                    json={"square_meters": 70, "building": {"comune": "Firenze"}})
        rows = client.get(f"{API}/surveys", headers=headers).json()
        assert rows[0]["comune"] == "Firenze"
