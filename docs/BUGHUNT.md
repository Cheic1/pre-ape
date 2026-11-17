# Caccia ai bug (funzioni AI)

`backend/tests/test_bughunt_ai.py` gira senza rete e senza costi:

- **LLM dispettoso**: risposte malformate (messaggio nullo, tool call non valide,
  argomenti non JSON, tipi sbagliati nel JSON finale, cicli infiniti). Regola:
  il consulente deve dare un risultato valido o un `AdvisorError` (502), mai un 500.
- **Fuzz di `parse_hints`** (planimetria): testo casuale dal modello.
- **Property-based (Hypothesis)** sul motore: classe sempre A4…G, numeri finiti,
  più isolamento non peggiora mai l'EP, incentivo ≤ investimento.

```bash
cd backend && python -m pytest tests/test_bughunt_ai.py -q
```

## Delegare il giro successivo a un agente economico (opencode, ecc.)

Prompt da incollare, con un modello economico:

> Nel repo pre-ape leggi AGENTS.md e `backend/tests/test_bughunt_ai.py`.
> Scegli UN modulo fra `app/core/catasto/visura.py`, `app/core/planimetria/walls.py`,
> `app/api/v1/documents.py`, `app/api/v1/admin.py`. Cerca input che causano
> eccezioni non gestite (500) o risultati incoerenti. Per ogni sospetto scrivi un
> test in `tests/test_bughunt_<modulo>.py` che fallisce, poi la correzione minima.
> Non modificare i test esistenti. Esegui `python -m pytest tests/ -q` prima di finire
> e riassumi i bug trovati in una lista.
