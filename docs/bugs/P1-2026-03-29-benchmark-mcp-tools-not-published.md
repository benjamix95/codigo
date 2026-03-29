# P1 — i benchmark performance esistevano solo come script/test, non come tool MCP richiamabili

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: i benchmark performance del progetto erano presenti solo come script shell e test benchmark (`scripts/benchmark_*`, `ValidationPerformanceTests`, `CodebaseIndexIndexingBenchmarkSmokeTests`), ma non esistevano tool MCP dedicati pubblicati nel catalogo Rust/Swift.
- Sintomo: da chat non era possibile richiamare benchmark indexing/review-core come tool nativi; `tools/list` non mostrava alcun tool benchmark e non c'erano alias runtime/canonicali dedicati.
- Impatto: i benchmark erano utilizzabili solo manualmente da shell, non orchestrabili dal runtime tool/chat e non tracciabili come tool call MCP con payload strutturato.
- Gravità: P1
- Steps to reproduce:
  1. Cercare `benchmark_` nel catalogo MCP (`tool_names.txt`, `canonical_tool_registry.json`, `CoderIDETools.swift`).
  2. Eseguire `tools/list` sul server MCP Rust.
  3. Verificare che compaiano solo audit/perf tools e nessun benchmark runner dedicato.
- Risultato attuale: benchmark disponibili solo via script/test interni.
- Risultato atteso: benchmark esposti come tool MCP con schema, descrizione, alias e output strutturato.
- Causa probabile: le tranche precedenti hanno hardenizzato i benchmark script, ma non hanno completato il passaggio `script/test -> tool MCP`.
- Scope consentito:
  - catalogo canonico MCP
  - handler Rust MCP
  - schema tool Rust
  - catalogo Swift `CoderIDETools`
  - `ToolSchemaCatalog` engine
  - script benchmark esistenti solo per fix minimi di invocazione Xcode
- Non-scope: redesign degli script benchmark, refactor dei test benchmark interni, nuovi benchmark extra.
- Moduli confinanti da verificare: `tools/list`, `handlers.rs`, `tool_schema.rs`, `scripts/benchmark_indexing_pre_post.sh`, `scripts/benchmark_review_pipeline_pre_post.sh`, catalogo engine/Swift.
- Test da aggiungere o aggiornare:
  - contratto catalogo Rust
  - `ToolSchemaCatalogTests`
  - test unit Rust del wrapper benchmark
  - prova reale `tools/call` su entrambi i nuovi tool
- Strategia di fix minimo: creare due wrapper MCP sopra gli script esistenti:
  - `benchmark_indexing`
  - `benchmark_review_pipeline`
  pubblicarli nel registry canonico, generare gli artefatti Rust/Swift e restituire payload strutturato con i path degli artefatti benchmark.
- Verifica post-fix:
  1. `tools/list` mostra i due tool benchmark
  2. `tools/call` su `coderide_benchmark_indexing` produce JSON/log artifact
  3. `tools/call` su `coderide_benchmark_review_pipeline` produce engine/app JSON
  4. test Rust/Swift verdi
- Commit previsto: `feat(mcp): expose benchmark performance runners`
