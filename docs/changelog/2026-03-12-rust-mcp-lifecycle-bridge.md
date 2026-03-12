# 2026-03-12 — Rust MCP lifecycle bridge tranche 8

## Modifiche
- aggiunti:
  - [MCPLifecycleRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift)
  - [MCPLifecycleRustBinaryLocator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBinaryLocator.swift)
  - [MCPLifecycleRustBackend.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift)
  - [MCPSessionManager+RustLifecycleBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPSessionManager+RustLifecycleBridge.swift)
  - [build_rust_mcp_lifecycle_backend.sh](/Users/benjaminstoica/SoloCode/scripts/build_rust_mcp_lifecycle_backend.sh)
- aggiornati:
  - [MCPSessionManager.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManager.swift)
  - [MCPSessionManager+Lifecycle.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift)
  - [MCPSessionManager+Tools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Tools/MCPSessionManager+Tools.swift)
  - [MCPSessionManager+Metrics.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Metrics/MCPSessionManager+Metrics.swift)
  - [MCPSessionManagerTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/MCPSessionManagerTests.swift)
  - [build-app.sh](/Users/benjaminstoica/SoloCode/scripts/build-app.sh)
  - [run-app.sh](/Users/benjaminstoica/SoloCode/scripts/run-app.sh)
  - [validate_app_bundle.sh](/Users/benjaminstoica/SoloCode/scripts/validate_app_bundle.sh)
  - [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Cosa cambia
- `MCPSessionManager` instrada verso `mcp-lifecycle-backend-rust` le operazioni MCP generiche ad alta frequenza:
  - `health`
  - `listTools`
  - `callTool`
  - `callToolRich`
  - `reconnect`
  - `restartServer`
  - `shutdownAll`
- il bridge Rust usa un backend stdio persistente a linee JSON, con locator binario dedicato e cleanup del processo su errori di transport
- `serverMetrics` usa lo stato Rust per status e tool count, evitando di dipendere solo dalle sessioni Swift legacy
- i build script ora compilano e copiano nel bundle anche `mcp-lifecycle-backend-rust`
- aggiunto test di regressione Swift che usa esplicitamente il backend lifecycle Rust e un fake MCP server per verificare:
  - `listTools`
  - `callToolRich`
  - `health`
  - `restartServer`

## Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `./scripts/build_rust_mcp_server.sh`
- `./scripts/build_rust_mcp_lifecycle_backend.sh`
- audit sicurezza scoped:
  - `audit_security_patterns` sui file modificati, senza finding
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`

## Note
- `xcodebuild test` completo sul workspace continua a poter fallire per il problema già documentato di policy/code-sign del bundle `CoderEngineTests.xctest`
- `resources` e `prompts` MCP restano ancora sul path Swift legacy in questa tranche
