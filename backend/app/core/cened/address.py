"""Separa via e numero civico per i campi ``indirizzo`` / ``ncivico`` CENED.

Gli indirizzi del sopralluogo arrivano in tre forme:

* ``display_name`` di OpenStreetMap: ``"8, Via Pietro Spino, Carnovali, Bergamo, …"``
  (civico in testa, poi via, quartiere, comune…);
* scritti a mano: ``"Via Roma 1, Milano"`` o ``"Via Roma, 1"``;
* visura catastale: ``"VIA ROMA n. 10"``.

Si tiene solo la via (il comune va già nei campi propri) e il civico a parte.
Se il civico non si riconosce resta vuoto: il certificatore lo completa in CENED.
"""
from __future__ import annotations

import re
from typing import Optional, Tuple

# 8 · 12/A · 15b · 3-5 · 7 bis
_CIVICO = r"\d{1,5}(?:\s*[/-]\s*\w{1,4}|\s*[A-Za-z]{1,3}\b|\s+bis\b)?"
_CIVICO_RE = re.compile(rf"^(?:n\.?\s*)?({_CIVICO})$", re.IGNORECASE)
_TRAILING_RE = re.compile(rf"^(.*?\D)[\s,]+(?:n\.?\s*)?({_CIVICO})$", re.IGNORECASE)


def split_address(raw: Optional[str]) -> Tuple[str, str]:
    """``(via, civico)``; stringhe vuote se mancano."""
    parts = [p.strip() for p in (raw or "").split(",") if p.strip()]
    if not parts:
        return "", ""
    head = _CIVICO_RE.match(parts[0])
    if head and len(parts) > 1:  # formato OSM: "8, Via …"
        return parts[1], head.group(1).replace(" ", "")
    street = parts[0]
    if len(parts) > 1:
        nxt = _CIVICO_RE.match(parts[1])
        if nxt:  # "Via Roma, 1, Milano"
            return street, nxt.group(1).replace(" ", "")
    tail = _TRAILING_RE.match(street)
    if tail:
        return tail.group(1).strip(), tail.group(2).replace(" ", "")
    return street, ""
