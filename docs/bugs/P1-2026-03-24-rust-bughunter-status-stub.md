# P1 — bughunter_status_payload_from_review è sempre None (stub)

## Bug Fix Record
- Categoria: B - Importante
- Bug: `bughunter_status_payload_from_review` in `review_tools.rs:527-529` ritorna sempre `None`. Lo status del bughunter non viene mai mostrato quando richiesto via il tool review.
- Sintomo: Nessun payload di status bughunter visibile nelle risposte del review tool.
- Impatto: Informazioni mancanti per l'utente.
- Gravità: P1
- Strategia di fix minimo: Implementare la lettura delle snapshot bughunter e la costruzione del payload, come già fatto per `review_status_payload`.
- Commit previsto: `fix(mcp-rust): implement bughunter_status_payload_from_review`
