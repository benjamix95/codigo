# P1 — il trace chat dei benchmark MCP non mostrava gli artefatti prodotti

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: i nuovi tool MCP benchmark restituivano `structuredContent` con `output_json`, `log_file`, `summary_md`, `engine_json`, `app_json`, ma il mapper MCP non trasferiva quei campi nel `ToolTraceEvent`. In chat si vedeva solo la riga generica del tool, senza link agli artefatti.
- Sintomo: dopo l'esecuzione di `coderide_benchmark_indexing` o `coderide_benchmark_review_pipeline`, il trace mostrava il tool ma non rendeva i path degli artefatti benchmark.
- Impatto: i benchmark erano richiamabili, ma non realmente usabili dalla chat come output navigabile; si perdeva la parte piu' utile del wrapper MCP.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire un benchmark via `tools/call`.
  2. Osservare l'evento `mcp_tool_call` in chat/tool trace.
  3. Verificare l'assenza di `output_json` / `summary_md` / `engine_json` / `app_json` nel payload UI.
- Risultato attuale: trace senza link o sezione artefatti benchmark.
- Risultato atteso: trace con titolo leggibile benchmark, dettaglio `phase • tag` e sezione artefatti cliccabile.
- Causa probabile: `ProviderToolEventMapper+MapMCP.swift` appiattiva solo alcuni campi noti del JSON strutturato e ignorava quelli benchmark-specifici.
- Scope consentito:
  - `ProviderToolEventMapper+MapMCP.swift`
  - `MessageToolTraceView+Details.swift`
  - `MessageToolTraceView+Helpers.swift`
  - `MessageToolTraceView+EventMetadata.swift`
  - test mapper core
- Non-scope: redesign generale del trace UI, nuove persistenze artifact, refactor del `ToolTraceStore`.
- Moduli confinanti da verificare: `ProviderToolEventMapper`, `MessageToolTraceView`, test `ProviderToolEventMapperTests+Core`.
- Test da aggiungere o aggiornare:
  - test mapper MCP che verifica title friendly e copia dei campi artefatto benchmark
- Strategia di fix minimo: propagare i campi benchmark-specifici dal `structuredOutput` al payload evento e aggiungere una sezione benchmark dedicata nella detail view con pulsanti `onOpenFile`.
- Verifica post-fix:
  1. test Swift verdi sul mapper
  2. benchmark MCP eseguito realmente e artefatti visibili nel trace
- Commit previsto: `fix(ui): show benchmark artifacts in tool trace`
