# Changelog — 2026-03-29 — Advanced Perf MCP Tools

## Sommario
Pubblicati nel catalogo MCP i tool performance avanzati gia' presenti in RustCore e riallineate le descrizioni `tools/list` alle descrizioni canoniche del registry.

## Modifiche
- Aggiunti `coderide_audit_perf_correlate` e `coderide_audit_perf_trending` al source registry in [canonical_tool_registry.json](/Users/benjaminstoica/SoloCode/Config/tooling/canonical_tool_registry.json).
- Rigenerati gli artefatti catalogo:
  - [tool_names.txt](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_names.txt)
  - [tool_descriptions.json](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_descriptions.json)
  - [CoderIDECanonicalToolRegistry+Generated.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift)
  - [CoderIDETools+RustSyncedDescriptions.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+RustSyncedDescriptions.swift)
- Aggiornate costanti e schema Swift in [CodeReviewAuditModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Audit/CodeReviewAuditModels.swift) e [ToolSchemaCatalog+AuditTools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+AuditTools.swift).
- Esteso il dispatch audit in [UnifiedToolRuntime+RunCoreDispatch.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/UnifiedToolRuntime+RunCoreDispatch.swift).
- Corretto il lookup descrizioni in [tool_descriptions.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/tool_descriptions.rs): prima usa `tool_descriptions.json`, solo dopo il fallback audit generico.
- Aggiunti test in [PerformanceAuditToolIntegrationTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Audit/PerformanceAuditToolIntegrationTests.swift), [ToolSchemaCatalogTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolSchemaCatalogTests.swift) e [catalog_contract.rs](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/tests/catalog_contract.rs).

## Validazione
- `cargo test --test catalog_contract -- --nocapture` in `Native/CoderideMCPServerRust` -> verde
- `cargo test --test server_smoke initialize_and_list_tools_work -- --nocapture` in `Native/CoderideMCPServerRust` -> verde
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/WorkspaceCatalogToolTests` -> verde
- Probe reale su `tools/list` e `tools/call` del binary MCP:
  - `coderide_audit_perf_correlate` presente e invocabile
  - `coderide_audit_perf_trending` presente e invocabile
