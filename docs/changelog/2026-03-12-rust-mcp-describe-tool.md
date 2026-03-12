# 2026-03-12 — Rust MCP lifecycle tranche 11 (describe_tool)

## Modifiche
- aggiunti:
  - [describe_backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/describe_backend.rs)
- aggiornati:
  - [protocol.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/protocol.rs)
  - [backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/backend.rs)
  - [main.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/main.rs)
  - [backend_smoke.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/tests/backend_smoke.rs)
  - [MCPLifecycleRustBackend.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift)
  - [MCPLifecycleRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift)
  - [MCPSessionManager+Tools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Tools/MCPSessionManager+Tools.swift)
  - [MCPSessionManagerTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/MCPSessionManagerTests.swift)

## Cosa cambia
- il backend Rust supporta ora l’operazione dedicata `describe_tool`
- `MCPSessionManager.describeTool(...)` non ricostruisce più la descrizione passando da `listTools`, ma usa il path dedicato Rust-backed
- aggiunta copertura Rust e Swift per il caso `describe_tool`

## Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`

## Note
- il runner `xcodebuild test` completo resta bloccato dal problema infrastrutturale del bundle `CoderEngineTests.xctest`, documentato nel bug P2 già aperto
