# 2026-03-12 — Rust MCP server tranche 2 (plan e IDE state)

## Modifiche
- esteso `CoderideMCPServerRust` con shared state plan persistito su:
  - `~/Library/Application Support/CoderIDE/mcp-shared/plan_state.json`
- aggiunti handler Rust per:
  - `coderide_plan_create`
  - `coderide_plan_read`
  - `coderide_plan_history_read`
  - `coderide_plan_step_update`
  - `coderide_plan_step_upsert`
  - `coderide_plan_diff`
- aggiunti ack Rust per:
  - `coderide_policy_ack`
  - `coderide_mermaid_render`
  - `coderide_debug_session`
- introdotto il modulo `plan_state.rs` nel server Rust per:
  - snapshot plan
  - upsert step
  - diff snapshot
  - serializzazione JSON compatibile col formato MCP atteso dai client
- aggiornato il bug aperto sulla parità tool Rust per riflettere i nuovi handler già migrati

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `./scripts/build_rust_mcp_server.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testCallToolRichRecordsMetrics -only-testing:CoderEngineTests/MCPSessionManagerTests/testSubagentExplorerToolReturnsImmediateAck -only-testing:CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests/testSendPrewarmsCoderideToolsBeforeBuildingPrompt`

## Esito
- il server MCP Rust copre ora anche una porzione reale e persistita dello shared state plan
- il catalogo Rust continua a restare compatibile con i test engine che consumano `coderide-mcp-server`
- il cutover totale resta ancora bloccato dalla parità incompleta dei tool non ancora migrati
