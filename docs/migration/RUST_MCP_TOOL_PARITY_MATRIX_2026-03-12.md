# Rust MCP Tool Parity Matrix - 2026-03-12

## Baseline congelata
- Catalog version: `2026-03-12`
- Tool count: `131`
- Source of truth: `Native/CoderideMCPServerRust/src/tool_names.txt`
- Catalog metadata owner: `Native/CoderideMCPServerRust/src/catalog.rs`

## Famiglie incluse nella baseline
- `Audit`
- `BugHunter`
- `Codebase`
- `Debug`
- `Diagnostics`
- `Edit`
- `File`
- `Git`
- `Plan`
- `Policy`
- `Review`
- `Search`
- `Security`
- `Skill`
- `Subagent`
- `Todo`
- `Ui`
- `Web`

## Copertura minima verificata in questa tranche
- Ogni tool del catalogo ha:
  - nome stabile
  - descrizione non vuota
  - `readOnlyHint` coerente nel `tools/list`
  - appartenenza a una famiglia runtime
- Il server MCP Rust espone in `initialize`:
  - versione catalogo
  - conteggio tool

## Test che bloccano drift di contratto
- `catalog::tests::catalog_version_is_frozen_for_tranche`
- `catalog::tests::every_tool_name_has_exactly_one_spec`
- `catalog::tests::all_tools_expose_read_only_annotations`
- `catalog::tests::catalog_covers_core_families`
- `tests/catalog_contract.rs::tools_list_matches_frozen_catalog_size_and_annotations`

## Gap ancora aperti per le tranche successive
- parity tool-by-tool tra `UnifiedToolRuntime` Swift e server Rust
- rimozione dei path Swift con business logic tool-specifica
- completamento handler Rust per eliminare ogni fallback residuo prima del cutover unico
- validazione Apple-side via `xcodebuildmcp`
