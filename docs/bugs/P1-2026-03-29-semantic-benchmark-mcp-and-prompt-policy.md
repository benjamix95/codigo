# P1 — mancava il benchmark MCP per `semantic_search` e la prompt policy non suggeriva esplicitamente la famiglia diagnostics

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: dopo l’introduzione dei benchmark MCP per indexing e review-core, il benchmark sintetico di `semantic_search` restava disponibile solo come test XCTest. Inoltre la prompt policy non esponeva una sezione esplicita per la famiglia diagnostics/benchmark.
- Sintomo: nessun tool MCP per lanciare il benchmark semantic search da chat; il modello vedeva review/audit/bughunter ma non una family summary per diagnostics/benchmark.
- Impatto: benchmark performance incompleti lato MCP e discoverability ridotta nel prompt runtime.
- Gravità: P1
- Steps to reproduce:
  1. Cercare `benchmark_semantic_search` nel catalogo MCP e in `tools/list`.
  2. Cercare una sezione `Diagnostics family` in `PromptToolsPolicy`.
  3. Verificare che `SemanticSearchBenchmarkTests` non esporti JSON benchmark riusabile.
- Risultato attuale: nessun wrapper MCP per semantic benchmark, nessun output JSON benchmark dedicato, nessuna sezione diagnostics nella guidance tool.
- Risultato atteso: `coderide_benchmark_semantic_search` discoverable e invocabile, con artefatti JSON/log; prompt policy che espone anche la famiglia diagnostics.
- Causa probabile: copertura parziale della tranche benchmark MCP, focalizzata prima su indexing/review-core.
- Scope consentito:
  - `SemanticSearchBenchmarkTests.swift`
  - catalogo canonico + artefatti generati
  - modulo Rust benchmark
  - catalogo Swift/engine
  - `PromptToolsPolicy.swift`
  - test `SystemPromptsTests`
- Non-scope: nuovi benchmark extra oltre ai tre principali, redesign del prompt system.
- Moduli confinanti da verificare: `tool_names.txt`, `tool_schema.rs`, `ToolSchemaCatalog`, `SystemPrompts`, binary MCP Rust.
- Test da aggiungere o aggiornare:
  - `SystemPromptsTests` per diagnostics family + benchmark tool names
  - `ToolSchemaCatalogTests` per il nuovo tool runtime
  - test unit Rust del wrapper semantic benchmark
- Strategia di fix minimo: creare un wrapper MCP dedicato sopra `SemanticSearchBenchmarkTests`, far esportare al test un JSON riusabile e aggiungere la family summary diagnostics alla prompt policy.
- Verifica post-fix:
  1. `coderide_benchmark_semantic_search` presente in `tools/list`
  2. `tools/call` produce `output_json` e `log_file`
  3. `SystemPrompts.taskCompletionStrict` contiene `Diagnostics family` e i benchmark tool
- Commit previsto: `feat(mcp): add semantic benchmark runner and diagnostics prompt guidance`
