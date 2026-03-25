# P1 — Rust finding_map: message field estratto ma mai inserito nella map

## Bug Fix Record
- Categoria: B - Importante
- Bug: in `review_tools.rs`, la funzione `finding_map()` estrae il campo `message` dal JSON dell'item (riga 347), ma poi lo scarta con `let _ = message` (riga 398) senza mai inserirlo nella HashMap.
- Sintomo: i finding restituiti dal tool `review_findings` non contengono il campo `message`, perdendo informazione utile per l'utente.
- Impatto: l'agente che chiama `review_findings` non riceve il messaggio descrittivo del finding. Deve ri-leggere il file sorgente per capire di cosa si tratta.
- Gravita: P1
- Steps to reproduce:
  1. Eseguire una code review che produce findings con campo `message`.
  2. Chiamare il tool MCP `review_findings`.
  3. Verificare che il campo `message` non appare nell'output.
- Risultato attuale: `message` assente dall'output.
- Risultato atteso: `message` presente nella map restituita.
- Causa probabile: il campo era usato per validazione (`?` operator forza presence), ma l'inserimento nella map e stato dimenticato. Il `let _ = message` sopprime il warning del compilatore.
- Scope consentito: `review_tools.rs`, funzione `finding_map()`
- Non-scope: formato dei finding, logica di review, UI
- Strategia di fix minimo: sostituire `let _ = message` con `map.insert("message".to_string(), message)`
- Verifica post-fix: cargo check passa, il campo message appare nell'output di `review_findings`
- Commit previsto: `fix(rust-mcp): include message field in finding_map output`

## Fix applicato
- `review_tools.rs:398`: `let _ = message` → `map.insert("message".to_string(), message)`
