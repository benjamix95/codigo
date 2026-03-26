# P0 — debug_clean non matcha i marker inseriti da debug_mark

## Bug Fix Record
- Categoria: A - Critico
- Bug: `debug_clean` usa pattern `"DEBUG[marker]"` ma `debug_mark` inserisce `"[DEBUG:marker]"`. I pattern non matchano mai, rendendo impossibile la pulizia dei marker specifici.
- Sintomo: chiamando `debug_clean` con un `clean_type` specifico (es. `"breakpoint"`, `"log"`), nessun marker viene rimosso dal file. Solo `clean_type == "all"` funziona perché usa il pattern generico `"DEBUG"`.
- Impatto: I marker di debug restano nel codice sorgente e non possono essere rimossi selettivamente. Accumulo di marker inutili nei file.
- Gravità: P0
- Steps to reproduce:
  1. Chiamare `debug_mark` con `marker_type: "breakpoint"` su un file → inserisce `// [DEBUG:breakpoint]`.
  2. Chiamare `debug_clean` con `clean_type: "breakpoint"` sullo stesso file.
  3. Verificare che il marker è ancora nel file.
- Risultato attuale: `debug_clean` cerca `"debug[breakpoint]"` (dopo lowercase). Il testo nel file è `"[debug:breakpoint]"`. La stringa `"[debug:breakpoint]"` NON contiene `"debug[breakpoint]"` (colon vs no-colon, bracket position diversa). Nessuna riga viene rimossa.
- Risultato atteso: `debug_clean` deve rimuovere correttamente i marker inseriti da `debug_mark` per ogni `clean_type`.
- Causa probabile: Mismatch tra il formato di inserimento (`[DEBUG:type]`) e il formato di ricerca (`DEBUG[type]`). Probabilmente un errore di copia/incolla durante l'implementazione.
- Scope consentito: `Native/CoderideMCPServerRust/src/debug_tools.rs` — funzione `debug_clean`, linee 836-841 (pattern generation) e confronto linea 856.
- Non-scope: formato dei marker inseriti da `debug_mark` (quello è il formato canonico), `debug_instrument`.
- Moduli confinanti da verificare: `debug_mark` (per confermare il formato esatto inserito), `write_lines` (per verificare che la scrittura post-clean sia corretta).
- Test da aggiungere o aggiornare:
  - Test: `debug_mark` + `debug_clean` roundtrip per ogni `marker_type`.
  - Test: `debug_clean` con `clean_type: "all"` rimuove tutti i marker.
  - Test: `debug_clean` con `clean_type` specifico rimuove solo quel tipo.
- Strategia di fix minimo: Allineare i pattern in `debug_clean` al formato reale `[DEBUG:type]`. Cambiare le pattern da `"DEBUG[{type}]"` a `"[DEBUG:{type}]"`.
- Verifica post-fix:
  1. Roundtrip test mark → clean per breakpoint, log, trace, guard.
  2. Verifica che `clean_type: "all"` continui a funzionare.
  3. `cargo test` sull'intero crate.
- Commit previsto: `fix(mcp-rust): align debug_clean patterns with debug_mark format`
