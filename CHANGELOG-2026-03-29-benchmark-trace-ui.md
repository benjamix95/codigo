# Changelog — 2026-03-29 — Benchmark Trace UI

## Sommario
Migliorato il trace UI dei benchmark MCP: i payload benchmark vengono ora appiattiti nel `ToolTraceEvent` e la chat mostra una sezione dedicata con gli artefatti prodotti.

## Modifiche
- In [ProviderToolEventMapper+MapMCP.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapMCP.swift):
  - aggiunta copia dei campi benchmark-specifici (`phase`, `tag`, `output_json`, `log_file`, `summary_md`, `engine_json`, `app_json`, `stdout`, `stderr`)
  - titolo friendly per:
    - `benchmark_indexing`
    - `benchmark_review_pipeline`
  - `detail` compatto impostato a `phase • tag`
- In [MessageToolTraceView+EventMetadata.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+EventMetadata.swift):
  - icone dedicate per i due benchmark tool
- In [MessageToolTraceView+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Helpers.swift):
  - `compactDetail` benchmark-specifico con `phase`, `tag` e stato artefatti
- In [MessageToolTraceView+Details.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+Details.swift):
  - nuova sezione `Benchmark Artifacts`
  - pulsanti per aprire JSON/log/summary prodotti dal benchmark
- Aggiornato il test mapper in [ProviderToolEventMapperTests+Core.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ProviderToolEventMapper/ProviderToolEventMapperTests+Core.swift).

## Validazione
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ProviderToolEventMapperTests_Core -only-testing:CoderEngineTests/ToolSchemaCatalogTests` -> verde
- Probe reale benchmark MCP:
  - `coderide_benchmark_indexing` -> completato con payload artefatti
  - `coderide_benchmark_review_pipeline` -> completato con payload artefatti
