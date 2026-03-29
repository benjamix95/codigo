# Changelog — 2026-03-29 — Semantic Benchmark MCP And Prompt Policy

## Sommario
Aggiunto il terzo benchmark MCP per `semantic_search` e aggiornata la prompt policy per esporre in modo esplicito la famiglia diagnostics/benchmark al modello.

## Modifiche
- Esteso [SemanticSearchBenchmarkTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/SemanticSearch/SemanticSearchBenchmarkTests.swift) per esportare un JSON benchmark quando `SOLOCODE_SEMANTIC_BENCHMARK_OUTPUT` è impostato.
- Creato il wrapper Rust dedicato [benchmark_tools_semantic.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/benchmark_tools_semantic.rs) e collegato in:
  - [benchmark_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/benchmark_tools.rs)
  - [main.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/main.rs)
- Pubblicato `coderide_benchmark_semantic_search` nel catalogo:
  - [canonical_tool_registry.json](/Users/benjaminstoica/SoloCode/Config/tooling/canonical_tool_registry.json)
  - [tool_schema.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_schema.rs)
  - [tool_names.txt](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_names.txt)
  - [tool_descriptions.json](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_descriptions.json)
  - [CoderIDECanonicalToolRegistry+Generated.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift)
  - [CoderIDETools+Execution.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+Execution.swift)
  - [ToolSchemaCatalog+RuntimeTools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+RuntimeTools.swift)
- Aggiornata [PromptToolsPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift) con la sezione `Diagnostics family`.
- Aggiornati i test:
  - [ToolSchemaCatalogTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolSchemaCatalogTests.swift)
  - [SystemPromptsTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/SystemPromptsTests.swift)

## Validazione
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/SemanticSearchBenchmarkTests` -> verde
- Probe reale `tools/call` su `coderide_benchmark_semantic_search` con `HOME` reale -> completata, con `output_json` e `log_file`
