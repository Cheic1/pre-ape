"""Separazione via / numero civico per l'export CENED (pure, niente DB)."""
import pytest

from app.core.cened.address import split_address


@pytest.mark.parametrize("raw, expected", [
    # display_name di OpenStreetMap/Nominatim: civico in testa
    ("8, Via Pietro Spino, Carnovali, Bergamo, Lombardia, 24126, Italia", ("Via Pietro Spino", "8")),
    ("12/A, Via Roma, Milano, Lombardia, Italia", ("Via Roma", "12/A")),
    # OSM senza civico
    ("Via Pietro Spino, Carnovali, Bergamo, Lombardia, Italia", ("Via Pietro Spino", "")),
    # scritto a mano
    ("Via Roma 1, Milano", ("Via Roma", "1")),
    ("Via Roma, 1, Milano", ("Via Roma", "1")),
    ("Via Roma 1", ("Via Roma", "1")),
    ("Corso Italia 15b", ("Corso Italia", "15b")),
    # visura catastale
    ("VIA ROMA n. 10", ("VIA ROMA", "10")),
    ("VIA XX SETTEMBRE n. 4", ("VIA XX SETTEMBRE", "4")),
    ("Via XX Settembre", ("Via XX Settembre", "")),  # numero romano/nome, non civico
    ("Piazza 4 Novembre", ("Piazza 4 Novembre", "")),
    ("  ", ("", "")),
    (None, ("", "")),
])
def test_split_address(raw, expected):
    assert split_address(raw) == expected
