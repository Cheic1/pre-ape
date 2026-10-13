"""Builds app/data/comuni_climatici.csv (zona climatica + gradi giorno per comune).

Sources:
- DPR 412/93 Allegato A (testo coordinato con DM 16/05/1995 e DM 06/10/1997),
  e.g. https://nazionale.anaip.it/wp-content/uploads/dpr412-93_allA_tabellagradigiorno-riscaldamento.pdf
  converted with `pdftotext -layout dpr.pdf dpr.txt` -> authoritative zone/GG/altitude.
- Current ISTAT comuni list (codice, provincia, regione, coordinate) from the
  Italy.Core SQLite db (https://github.com/N0T-A-NUMB3R/Italy.Core, src/Italy.Core/data/italy.db).
  Its own climate columns are used only for comuni created after 1997 (fusioni),
  because MB/BT carry placeholder values and the NA province is missing there.

Usage: python scripts/build_climate_data.py dpr.txt italy.db app/data/comuni_climatici.csv
"""
import csv
import re
import sqlite3
import sys
import unicodedata
from collections import defaultdict

# Provinces created after 1993: where their comuni were listed in the DPR table.
_OLD_PROVINCE = {
    "MB": {"MI"}, "BT": {"BA", "FG"}, "FM": {"AP"}, "SU": {"CA", "CI", "VS", "MD"},
    "VB": {"NO"}, "BI": {"VC"}, "LC": {"CO", "BG"}, "LO": {"MI"}, "PO": {"FI"},
    "RN": {"FO"}, "FC": {"FO"}, "KR": {"CZ"}, "VV": {"CZ"}, "CA": {"CA"},
    "NU": {"NU", "OG"}, "SS": {"SS", "OT"}, "OR": {"OR", "NU"}, "PU": {"PS"},
}

# Comuni created after 1997 by splitting another one: use the parent's values.
_SPLIT_FROM = {"correzzana": "lesmo"}

ROW = re.compile(r"^\s*([A-Z]{2})\s+([A-F])\s+(\d{2,4})\s+(\d{1,4})\s+(\S.*?)\s*$")


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z]", "", s)


def zone_for_gg(gg: int) -> str:
    return "A" if gg <= 600 else "B" if gg <= 900 else "C" if gg <= 1400 else \
        "D" if gg <= 2100 else "E" if gg <= 3000 else "F"


def main(dpr_txt: str, db_path: str, out: str) -> None:
    dpr = defaultdict(list)
    for line in open(dpr_txt, encoding="utf-8"):
        m = ROW.match(line)
        if m:
            name = re.sub(r"\s*\(\d+\)\s*$", "", m[5]).strip()
            dpr[norm(name)].append((m[1], m[2], int(m[3]), int(m[4]), name))

    db = sqlite3.connect(db_path)
    rows, used = [], set()
    for istat, name, prov, reg, zona, gg, alt, lat, lon in db.execute(
        "select codice_istat, denominazione, sigla_provincia, nome_regione, zona_climatica,"
        " gradi_giorno, altitudine, latitudine, longitudine from comuni where is_attivo=1"
    ):
        cands = dpr.get(_SPLIT_FROM.get(norm(name), norm(name)), [])
        provs = {prov} | _OLD_PROVINCE.get(prov, set())
        match = [c for c in cands if c[0] in provs] or (cands if len(cands) == 1 else [])
        if match:
            p, zona, gg, alt, _ = match[0]
            used.add((norm(name), p))
            src = "DPR412"
        elif prov in ("MB", "BT"):
            print("skip (no reliable data):", name, prov, file=sys.stderr)
            continue
        else:
            src = "ISTAT"
        rows.append([istat, name, prov, reg, zona, gg, alt or "", lat or "", lon or "", src])

    # Comuni missing from the ISTAT db (whole NA province): take them from the DPR table.
    have = {(norm(r[1]), r[2]) for r in rows}
    regions = {r[2]: r[3] for r in rows}
    regions.setdefault("NA", "Campania")
    for key, cands in dpr.items():
        for p, zona, gg, alt, name in cands:
            if p == "NA" and (key, p) not in have:
                rows.append(["", name, p, regions[p], zona, gg, alt, "", "", "DPR412"])

    rows.sort(key=lambda r: (norm(r[1]), r[2]))
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["istat", "comune", "provincia", "regione", "zona", "gradi_giorno",
                    "altitudine", "lat", "lon", "fonte"])
        w.writerows(rows)
    print(f"{len(rows)} comuni -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
