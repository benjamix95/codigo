# Changelog — 2026-03-30 — Tool-first prompt and subagent start fix

## Problema corretto

- Codex e Claude potevano ancora emettere testo filler prima dei tool, ad esempio “Ricevuto” o “Ingerisco la policy”.
- Questo ritardava o bloccava l’avvio diretto dei tool MCP e dei `subagent_*`.
- Il problema era nel layer prompt/policy, non nel server MCP.

## Fix applicato

- [InstructionPolicyBundle.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Policy/InstructionPolicyBundle.swift)
  - `policy_ack` ora è richiesto in modo esplicitamente silenzioso
  - vietati i filler user-facing prima della tool call
- [ToolEnabledLLMProvider+Policy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift)
  - rimossa la policy `USER-FACING UPDATE FIRST`
  - il path corretto è ora tool-first
  - il pattern corretto parte direttamente con `policy_ack` e `subagent_*`
- [ChatPanelView+PartO_Streaming1.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_Streaming1.swift)
  - vietato il preambolo naturale prima di `policy_ack` e `subagent_*`
- [CLIProfileProvisioner+Templates.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Templates.swift)
  - persistita la regola “no filler before tools”
- [codex_app_server_prompt.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server_prompt.rs)
  - Codex prompt aggiornato a tool-first e ack silenzioso
- [claude.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/claude.rs)
  - Claude prompt aggiornato per partire con tool/MCP/subagent invece che con testo o todo obbligatorio

## Copertura aggiunta/aggiornata

- [InstructionPolicyBundleTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/InstructionPolicyBundleTests.swift)
- [ToolEnabledLLMProviderSubagentPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests.swift)
- [CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift)
- test Rust in [claude.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/claude.rs)

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml coderide_system_prompt_starts_with_tools_not_filler -- --nocapture` -> verde
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -derivedDataPath '/tmp/solocode-dd-subagent' -only-testing:CoderEngineTests/InstructionPolicyBundleTests -only-testing:CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerInstructionSyncSubagentRoutingTests` -> verde
