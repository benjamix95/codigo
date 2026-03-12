# 2026-03-12 — Rust MCP server tranche 3 (plan parity estesa)

## Modifiche
- esteso `Native/CoderideMCPServerRust/src/plan_state.rs` per coprire altri tool `plan_*` ancora Swift-owned:
  - `coderide_plan_step_batch_update`
  - `coderide_plan_step_reorder`
  - `coderide_plan_step_dependency_set`
  - `coderide_plan_set_walkthrough`
  - `coderide_plan_request_user_input`
- allineata la serializzazione del documento plan Rust al formato camelCase condiviso con Swift:
  - `latestConversationId`
  - `snapshotsByConversation`
  - `snapshotId`
  - `chosenPath`
  - `walkthroughMarkdown`
  - `targetFile`
  - `linkedFiles`
  - `dependsOn`
  - `updatedAt`
- estesa la suite `server_smoke.rs` per verificare i nuovi tool di plan parity in processo reale

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `./scripts/build_rust_mcp_server.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testCallToolRichRecordsMetrics`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests/testSendPrewarmsCoderideToolsBeforeBuildingPrompt`

## Esito
- la copertura Rust del blocco `plan_*` lato MCP locale è sensibilmente più vicina alla parità con il server Swift legacy
- il formato di shared state plan non diverge più per naming rispetto alla controparte Swift
- restano ancora da migrare i tool MCP non-plan e la logica runtime completa prima di un cutover totale
