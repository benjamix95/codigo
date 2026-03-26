# P0 — Vector DB & Search Tools: 6/8 MCP Search Tools Non Funzionanti

**Data**: 2026-03-25
**Categoria**: A — Critico
**Scope**: Native/CoderideMCPServerRust, Engine/CoderEngine/Sources/CodebaseIndex

---

## Sommario

L'intero stack di ricerca esposto dal MCP server Rust è **non funzionante**. 6 tool su 8 falliscono perché dipendono da `rg` (ripgrep) che non è nel PATH del processo MCP server. Inoltre, `coderide_semantic_search` e `coderide_codebase_search` non usano il SemanticIndex reale — sono semplici wrapper grep.

---

## BUG-1: `coderide_semantic_search` è un grep mascherato

- **File**: `Native/CoderideMCPServerRust/src/diagnostics_tools.rs:58-63`
- **Sintomo**: Chiama `rg -n --no-heading <query>` — grep testuale puro
- **Impatto**: Nessun ranking BM25, nessun AST chunking, nessun scoring semantico. Il tool mente sulla sua natura.
- **Causa**: Il MCP server Rust è un processo separato senza accesso al `SemanticIndex` (actor Swift in-process)
- **Fix proposto**: Connettere via FFI bridge o IPC al SemanticIndex reale, oppure implementare BM25 scoring lato Rust

## BUG-2: `coderide_semantic_search` fallisce — rg non nel PATH

- **File**: `Native/CoderideMCPServerRust/src/diagnostics_tools.rs:58` → `Command::new("rg")`
- **Sintomo**: `No such file or directory (os error 2)`
- **Impatto**: Tool completamente non funzionante
- **Causa**: `rg` non è installato come binario standalone. È solo una funzione shell wrapper di Claude Code.

## BUG-3: `coderide_grep` e altri 5 tool falliscono — stessa causa

- **File**: `Native/CoderideMCPServerRust/src/search_tools.rs:163` → `run_rg()`
- **Tool rotti**: `coderide_grep`, `coderide_glob`, `coderide_find_files`, `coderide_find_symbol`, `coderide_find_references`, `coderide_codebase_search`
- **Impatto**: 6/8 tool di ricerca nel MCP server sono completamente inutilizzabili

## BUG-4: `coderide_codebase_search` non usa l'indice codebase

- **File**: `Native/CoderideMCPServerRust/src/search_tools.rs:152-160`
- **Sintomo**: Fa solo `rg -n --no-heading -e <query>`, ignora `CodebaseIndex`, `symbolsByName`, ecc.
- **Impatto**: Nessuna ricerca strutturale o indicizzata

---

## Tool funzionanti vs rotti

| Tool | Stato | Motivo |
|---|---|---|
| `coderide_semantic_search` | **ROTTO** | rg non nel PATH |
| `coderide_grep` | **ROTTO** | rg non nel PATH |
| `coderide_glob` | **ROTTO** | rg non nel PATH |
| `coderide_codebase_search` | **ROTTO** | rg non nel PATH |
| `coderide_find_files` | **ROTTO** | rg non nel PATH |
| `coderide_find_symbol` | **ROTTO** | rg non nel PATH |
| `coderide_find_references` | **ROTTO** | rg non nel PATH |
| `coderide_read_range` | **OK** | Usa fs::read_to_string |
| `coderide_file_outline` | **OK** | Usa fs::read_to_string |

---

## Fix raccomandato

### Opzione A — Bundlare ripgrep
Includere il binario `rg` nell'app bundle e aggiungere il percorso al PATH del processo MCP server.

### Opzione B — Fallback a grep/find nativi
In `run_rg()`, se `rg` non è disponibile, fallback a:
- `grep -rn` per content search
- `find` per file listing
- `grep -E` per regex search

### Opzione C — Ricerca in-process
Implementare ricerca file/contenuto in Rust puro (walkdir + regex) senza dipendenze esterne.

### Per semantic_search specificamente
Connettere al SemanticIndex reale via:
- FFI bridge (come già fatto per `RustSearchFFIClient`)
- Unix domain socket IPC
- Shared memory per lo snapshot dell'indice
