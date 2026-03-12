# 2026-03-12 — Rust MCP lifecycle bridge tranche 9 (resources/prompts)

## Modifiche
- aggiunti:
  - [resource_prompt_backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/resource_prompt_backend.rs)
  - [mcp_models.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/mcp_models.rs)
  - [backend_tests.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/backend_tests.rs)
- aggiornati:
  - [protocol.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/protocol.rs)
  - [backend.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/backend.rs)
  - [main.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/main.rs)
  - [mcp_process.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/mcp_process.rs)
  - [fake_mcp_server.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/bin/fake_mcp_server.rs)
  - [backend_smoke.rs](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/tests/backend_smoke.rs)
  - [MCPLifecycleRustBackend.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift)
  - [MCPLifecycleRustModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift)
  - [MCPSessionManager+RustLifecycleBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPSessionManager+RustLifecycleBridge.swift)
  - [MCPSessionManager+Resources.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Resources/MCPSessionManager+Resources.swift)
  - [MCPSessionManager+Prompts.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Prompts/MCPSessionManager+Prompts.swift)
  - [MCPSessionManager+Metrics.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Metrics/MCPSessionManager+Metrics.swift)
  - [MCPSessionManagerTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/MCPSessionManagerTests.swift)

## Cosa cambia
- il backend Rust `mcp-lifecycle-backend-rust` supporta ora anche:
  - `list_resources`
  - `read_resource`
  - `subscribe_resource`
  - `unsubscribe_resource`
  - `list_resource_templates`
  - `list_prompts`
  - `get_prompt`
- il fake MCP server di test espone risorse e prompt finti per copertura end-to-end del protocollo
- `MCPSessionManager` instrada sul backend Rust anche tutto il path `resources/prompts`, incluse subscribe/unsubscribe
- `serverMetrics` legge via Rust anche il conteggio di resources e prompts
- il crate Rust è stato rifattorizzato per rispettare i limiti di manutenzione del repo:
  - `backend.rs` e `mcp_process.rs` sono rientrati sotto 300 righe

## Validazione eseguita
- `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
- `bash scripts/build_rust_mcp_lifecycle_backend.sh`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests`

## Esito
- la build Rust e la build Swift del layer MCP sono verdi
- il run `xcodebuild test` continua a essere bloccato dal problema infrastrutturale di firma del bundle `CoderEngineTests.xctest`, già documentato separatamente
