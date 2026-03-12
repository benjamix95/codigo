# 2026-03-12 — Rust MCP lifecycle tranche 12 (server discovery source)

## Modifiche
- aggiornati:
  - [protocol.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/protocol.rs)
  - [backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/backend.rs)
  - [MCPLifecycleRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift)
  - [MCPSessionManager+RustLifecycleBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPSessionManager+RustLifecycleBridge.swift)
  - [MCPSessionManager+Lifecycle.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift)

## Cosa cambia
- `ServerConfig` lato Rust include ora anche `source`
- `list_servers` del backend Rust restituisce `source` insieme a `id`, `name` e `status`
- `MCPSessionManager.listServers()` usa il path Rust-backed quando disponibile, invece di dipendere solo dal resolver Swift locale

## Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`

## Note
- il runner `xcodebuild test` resta bloccato dal problema infrastrutturale di firma del bundle `CoderEngineTests.xctest`, documentato nel bug P2 già aperto
