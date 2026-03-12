# 2026-03-12 — Rust MCP lifecycle tranche 10 (batch)

## Modifiche
- aggiunti:
  - [batch_backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/batch_backend.rs)
  - [MCPLifecycleRustBackend+Batch.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend+Batch.swift)
  - [MCPSessionManager+RustLifecycleBatch.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPSessionManager+RustLifecycleBatch.swift)
- aggiornati:
  - [protocol.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/protocol.rs)
  - [backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/backend.rs)
  - [main.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/main.rs)
  - [backend_smoke.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/tests/backend_smoke.rs)
  - [MCPLifecycleRustBackend.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift)
  - [MCPLifecycleRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift)
  - [MCPSessionManager+Tools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Tools/MCPSessionManager+Tools.swift)
  - [MCPSessionManagerTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/MCPSessionManagerTests.swift)
  - [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Cosa cambia
- il backend Rust `mcp-lifecycle-backend-rust` gestisce ora anche `call_tools_batch`
- `MCPSessionManager.callToolsBatch(...)` usa il backend Rust per l’esecuzione batch e mantiene il vecchio fallback Swift solo in caso di errore del bridge
- il fake MCP server e gli smoke test Rust coprono anche il caso batch con successi ed errori ordinati per indice
- aggiunto test Swift di regressione sul path batch Rust-backed

## Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- audit sicurezza scoped senza finding

## Note
- `xcodebuild test` continua a essere bloccato dal problema infrastrutturale del runner `xctest`, documentato separatamente
