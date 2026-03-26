# P1 — Risultati write silenziosamente ignorati nel Rust MCP server

## Bug Fix Record
- Categoria: B - Importante
- Bug: In `review_tools.rs`, le chiamate a `state::write_review_commands(...)`, `state::write_bughunter_commands(...)`, etc. sono wrappate in `let _ = ...`, ignorando silenziosamente qualsiasi errore di scrittura.
- Sintomo: Su disco pieno, permessi mancanti o I/O error, l'utente riceve "OK" ma i dati non sono mai stati persistiti.
- Impatto: Perdita silenziosa di comandi e stato. L'utente crede che l'operazione sia riuscita.
- Gravità: P1
- Steps to reproduce:
  1. Rendere la directory di stato read-only.
  2. Chiamare `review_start`.
  3. Osservare risposta "OK" nonostante la write sia fallita.
- Risultato attuale: `let _ = state::write_review_commands(&queued.commands)` — errore ignorato.
- Risultato atteso: Propagare l'errore e restituire un messaggio di errore all'utente.
- Scope consentito: `review_tools.rs` linee 75, 117, 147, 182 e pattern simili in `debug_tools.rs`.
- Strategia di fix minimo: Sostituire `let _ = ...` con `...?` e propagare l'errore come `CallToolResult` con `is_error: true`.
- Commit previsto: `fix(mcp-rust): propagate write errors instead of silently discarding`
