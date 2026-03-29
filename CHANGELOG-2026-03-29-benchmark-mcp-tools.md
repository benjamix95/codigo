# Changelog — 2026-03-29 — Benchmark MCP Tools

## Sommario
Aggiunti due veri tool MCP per lanciare i benchmark performance gia' presenti nel repo e resi richiamabili dalla chat con alias, schema e output strutturato.

## Modifiche
- Aggiunti nel registry canonico:
  - `coderide_benchmark_indexing`
  - `coderide_benchmark_review_pipeline`
  in [canonical_tool_registry.json](/Users/benjaminstoica/SoloCode/Config/tooling/canonical_tool_registry.json)
- Creato handler Rust isolato in [benchmark_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/benchmark_tools.rs) con:
  - validazione argomenti
  - risoluzione repo root
  - esecuzione degli script benchmark
  - payload strutturato con path artefatti e stdout/stderr
- Collegato il modulo benchmark in:
  - [main.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/main.rs)
  - [handlers.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/handlers.rs)
  - [tool_schema.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_schema.rs)
  - [catalog.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/catalog.rs)
- Aggiunte le entry lato catalogo engine/Swift in:
  - [ToolSchemaCatalog+RuntimeTools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+RuntimeTools.swift)
  - [CoderIDETools+Execution.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+Execution.swift)
- Rigenerati gli artefatti derivati:
  - [tool_names.txt](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_names.txt)
  - [tool_descriptions.json](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_descriptions.json)
  - [CoderIDECanonicalToolRegistry+Generated.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift)
  - [CoderIDETools+RustSyncedDescriptions.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+RustSyncedDescriptions.swift)
- Corretto l’invocazione Xcode dei runner benchmark per usare combinazioni gia' validate:
  - [benchmark_indexing_pre_post.sh](/Users/benjaminstoica/SoloCode/scripts/benchmark_indexing_pre_post.sh) -> `Solo Code.xcodeproj` + `CoderEngineTests-Debug`
  - [benchmark_review_pipeline_pre_post.sh](/Users/benjaminstoica/SoloCode/scripts/benchmark_review_pipeline_pre_post.sh) -> `Solo Code.xcodeproj` + `Solo Code`

## Validazione
- `cargo test` in `Native/CoderideMCPServerRust` -> verde
- `cargo test --test catalog_contract -- --nocapture` -> verde
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolSchemaCatalogTests` -> verde
- Prova reale `tools/call` con `HOME` reale dell’utente:
  - `coderide_benchmark_indexing` fase `pre` -> completato, artefatti scritti in `docs/benchmarks/indexing-hardening/`
  - `coderide_benchmark_review_pipeline` fase `pre` -> completato, artefatti scritti in `docs/benchmarks/review-core/`
