# Changelog — 2026-03-30 — Recovery del primo round subagent dopo fallback `fork_context`

## Problema corretto

- Il modello poteva emettere nel primo round un testo di fallback sul `fork_context` invece di usare `subagent_*`.
- Quel testo passava come round valido, quindi il runtime non apriva nessun child agent reale.

## Fix applicato

- [ToolEnabledLLMProvider+SendRoundProcessing.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+SendRoundProcessing.swift)
  - riconosce il testo di fallback `fork_context` nel primo round
  - non lo tratta come round valido/visibile
- [ToolEnabledLLMProvider+Send.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+Send.swift)
  - forza una continuation round correttiva
  - aggiunge un follow-up prompt che impone `subagent_*` e vieta la narrazione del fork
- [ToolEnabledLLMProvider+ToolIntrospection.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Tools/ToolEnabledLLMProvider+ToolIntrospection.swift)
  - centralizza il riconoscimento del testo di fallback `fork_context`
- [codex_app_server_prompt.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server_prompt.rs)
  - rimuove la preferenza implicita per collaboration/fork nativi
  - riallinea il transport Codex ai `subagent_*` canonici quando disponibili
- [claude.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/claude.rs)
  - stesso riallineamento lato Claude transport

## Nuovi guardrail

- [ToolEnabledLLMProviderSubagentFallbackContinuationTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolEnabledLLMProviderSubagentFallbackContinuationTests.swift)
  - verifica esplicitamente che:
    - il primo round non lasci uscire il testo `fork_context`
    - il runtime continui da solo
    - venga lanciato almeno un subagent reale

## Verifiche eseguite

- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet` -> 340 test verdi
- `cargo test --manifest-path Native/RustCore/Cargo.toml coderide_system_prompt_prefers_solocode_subagent_tools_when_available -- --nocapture` -> verde
- `cargo test --manifest-path Native/RustCore/Cargo.toml merged_codex_base_instructions_appends_provider_prompt -- --nocapture` -> verde
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - mirati subagent/policy -> verdi
  - suite larga Codex/MCP/interleaving/wire -> verde
