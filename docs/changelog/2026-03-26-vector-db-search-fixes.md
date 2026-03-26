# Vector DB & Search Tools — Fix Changelog (2026-03-26)

## Riepilogo

Fix completo dei tool di ricerca del MCP Server Rust (`CoderideMCPServerRust`).
Tutti i 9 test di integrazione passano (erano 8/9 prima dei fix).

---

## Fix applicati

### FIX-1: `coderide_semantic_search` — da grep puro a ricerca multi-term con scoring
- **File**: `Native/CoderideMCPServerRust/src/diagnostics_tools.rs`
- **Problema**: `coderide_semantic_search` era un wrapper attorno a `rg -n --no-heading <query>` — ricerca testuale pura, non semantica
- **Fix**: Implementata tokenizzazione della query con filtraggio stop words, ricerca multi-term indipendente, scoring per file:line basato su quanti termini distinti matchano, ordinamento per rilevanza decrescente
- **Categoria**: P0 — Critico

### FIX-2: `coderide_codebase_search` — ricerca strutturata con scoring
- **File**: `Native/CoderideMCPServerRust/src/search_tools.rs`
- **Problema**: `codebase_search` faceva una singola ricerca `rg` senza scoring, ignorava parametri di filtraggio
- **Fix**: Implementata ricerca multi-term con scoring, supporto path scope, fallback su file stem dalla path quando la query è vuota, tokenizzazione con filtraggio stop words
- **Categoria**: P0 — Critico

### FIX-3: `HybridSearchEngineBackend` — eliminato rischio deadlock semaphore
- **File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift`
- **Problema**: Pattern `semaphore.wait()` su `Task {}` con `semaphore.signal()` poteva causare deadlock se il task veniva cancellato prima del signal
- **Fix**: Sostituito con `withCheckedContinuation` per entrambe le query (lexical e vector), eliminando completamente il rischio di deadlock
- **Categoria**: P1 — Importante

### FIX-4: `coderide_grep` — supporto parametri filtraggio
- **File**: `Native/CoderideMCPServerRust/src/search_tools.rs`
- **Problema**: `coderide_grep` ignorava `case_sensitive`, `context_lines`, `multiline`, `fileType`, `glob`, `output_mode`, `pathScope`
- **Fix**: Tutti i parametri vengono ora passati correttamente a `rg` come flag CLI
- **Categoria**: P1 — Importante

### FIX-5: Fallback nativo Rust quando `rg` (ripgrep) non è disponibile
- **File**: `Native/CoderideMCPServerRust/src/search_tools.rs`, `diagnostics_tools.rs`
- **Problema**: Tutti i tool di ricerca fallivano con "failed to execute rg" quando ripgrep non era installato come binario di sistema (es. in ambienti sandbox, CI, o dove `rg` è una shell function)
- **Fix**: `run_rg` ora tenta `rg` prima; se il binario non è trovato, usa un fallback nativo Rust con:
  - `native_walk_files()`: walk ricorsivo del filesystem con skip di directory nascoste/node_modules/target/build
  - `native_grep()`: ricerca testuale/regex tramite la crate `regex`, con supporto case-insensitive e limite a 500 risultati
  - `native_walk_recursive()`: helper ricorsivo per enumerazione file
- **Categoria**: P0 — Critico (il test di integrazione `search_tools_work` falliva)

---

## Stato test

| Test suite | Risultato |
|---|---|
| `search_tools_work` | ✅ PASS (era FAIL) |
| `diagnostics_and_audit_tools_work` | ✅ PASS |
| `editing_tools_work` | ✅ PASS |
| `debug_and_skill_tools_work` | ✅ PASS |
| `plan_tools_and_ide_acks_work` | ✅ PASS |
| `initialize_and_list_tools_work` | ✅ PASS |
| `review_security_and_bughunter_tools_work` | ✅ PASS |
| `todo_read_and_subagent_ack_work` | ✅ PASS |
| `plan_create_without_conversation_id` | ✅ PASS |
| **Totale** | **9/9 PASS** |

## File modificati

- `Native/CoderideMCPServerRust/src/search_tools.rs` (+246 righe)
- `Native/CoderideMCPServerRust/src/diagnostics_tools.rs` (+233 righe)
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift` (+50 righe)
