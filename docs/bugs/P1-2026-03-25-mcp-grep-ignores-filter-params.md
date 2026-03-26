# P1 — MCP Server: grep e semantic_search ignorano parametri di filtro

**Data**: 2026-03-25
**Categoria**: B — Importante
**Scope**: Native/CoderideMCPServerRust/src/search_tools.rs, diagnostics_tools.rs

---

## Bug

I tool `coderide_grep` e `coderide_semantic_search` dichiarano parametri avanzati nello schema (fileType, glob, case_sensitive, context_lines, multiline, pathScope, limit, min_confidence, target_directories, show_scoring, strict_scope) ma li ignorano completamente nell'implementazione.

## Dettaglio

### coderide_grep (search_tools.rs:61-72)

```rust
fn grep(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    // ...
    run_rg(workspace, &["-n", "--no-heading", pattern.as_str()])
    // ^^^ fileType, glob, case_sensitive, context_lines, multiline, pathScope: IGNORATI
}
```

### coderide_semantic_search (diagnostics_tools.rs:58-63)

```rust
fn semantic_search(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    shell_text("rg", &["-n", "--no-heading", query.as_str()], workspace)
    // ^^^ limit, min_confidence, path, pathScope, target_directories, show_scoring, strict_scope: IGNORATI
}
```

## Impatto

- Lo schema promette funzionalità che non esistono
- Gli agent costruiscono chiamate con parametri che vengono silenziosamente ignorati
- Risultati non filtrati quando l'utente si aspetta filtraggio

## Fix proposto

Mappare i parametri dello schema alle flag di rg:
- `fileType` → `--type` o `--glob '*.ext'`
- `glob` → `--glob`
- `case_sensitive: false` → `-i`
- `context_lines` → `-C N`
- `pathScope` → ricerca nella sotto-directory
