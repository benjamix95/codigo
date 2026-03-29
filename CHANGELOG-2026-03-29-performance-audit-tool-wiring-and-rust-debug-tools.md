# Changelog — 2026-03-29 — Performance Audit Tool Wiring And Rust Debug Tools

## Sommario
Allineati i tool performance audit lungo tutta la catena catalogo/runtime/chat e sbloccata la validazione Xcode riportando la copia locale di `Native/CoderideMCPServerRust/src/debug_tools.rs` alla versione corretta gia' presente nel repository.

## Modifiche
- Aggiunti i cinque tool `audit_perf_*` al source registry canonico in [canonical_tool_registry.json](/Users/benjaminstoica/SoloCode/Config/tooling/canonical_tool_registry.json) con descrizioni, flag read-only e alias runtime compatti.
- Rigenerati gli artefatti derivati:
  - [tool_names.txt](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_names.txt)
  - [tool_descriptions.json](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_descriptions.json)
  - [CoderIDECanonicalToolRegistry+Generated.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift)
  - [CoderIDETools+RustSyncedDescriptions.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+RustSyncedDescriptions.swift)
- Completato il dispatch runtime dei perf audit in [UnifiedToolRuntime+RunCoreDispatch.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/UnifiedToolRuntime+RunCoreDispatch.swift) così non risultano più unsupported nei percorsi rust-first/local fallback.
- Trattata la famiglia `audit` come read-only nella policy provider in [ToolEnabledLLMProvider+ToolStartPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Tools/ToolEnabledLLMProvider+ToolStartPolicy.swift).
- Esteso il synthetic event mapping della chat alla famiglia `audit` in [IDEStateSyntheticEventFactory.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Debug/Events/IDEStateSyntheticEventFactory.swift) e [IDEStateSyntheticEventFactory+Events.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Debug/Events/IDEStateSyntheticEventFactory+Events.swift) per mostrare correttamente i perf tool quando vengono chiamati.
- Durante la validazione, la copia locale di [debug_tools.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs) e' stata riallineata alla versione corretta gia' in `HEAD`, rimuovendo il compile blocker che fermava il phase script Xcode `Build Rust MCP Server`.
- Allineato il conteggio del catalogo e il contratto Rust in [catalog.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/catalog.rs) e [catalog_contract.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/tests/catalog_contract.rs).
- Aggiunti test di regressione in [PerformanceAuditToolIntegrationTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Audit/PerformanceAuditToolIntegrationTests.swift) e aggiornato [WorkspaceCatalogToolTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/WorkspaceCatalogToolTests.swift).

## Validazione
- `cargo test` in `Native/CoderideMCPServerRust` -> verde
- `cargo test tests_performance --lib` in `Native/RustCore` -> verde
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/PerformanceAuditToolIntegrationTests -only-testing:CoderEngineTests/WorkspaceCatalogToolTests -only-testing:CoderEngineTests/CoderIDECanonicalToolRegistryTests -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/CoderIDErustCatalogContractTests` -> verde
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:CoderEngineTests/PerformanceAuditToolIntegrationTests -only-testing:CoderEngineTests/WorkspaceCatalogToolTests -only-testing:CoderEngineTests/CoderIDECanonicalToolRegistryTests -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/CoderIDErustCatalogContractTests` -> verde
