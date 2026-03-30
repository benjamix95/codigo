# Changelog — 2026-03-30 — Rerouting subagent verso i tool canonici SoloCode

## Problema corretto

- Il main chat poteva privilegiare il path provider-native di fork/collaboration anche quando la sessione esponeva già i tool `subagent_*` di SoloCode.
- Questo produceva messaggi user-facing sui limiti `fork`/`fork_context` e impediva il lancio reale dei subagent con card visibili.

## Cosa ho cambiato

- [ChatPanelView+PartO_Streaming1.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_Streaming1.swift)
  - `subagent_*` diventa il path canonico quando è esposto nella live schema.
  - il provider-native fork è solo fallback quando `subagent_*` non esiste.
  - il modello non deve più raccontare al user limiti `fork`/`fork_context`.
- [CLIProfileProvisioner+Templates.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Templates.swift)
  - stesso riallineamento nelle istruzioni persistite del profilo Codex.
- [ToolEnabledLLMProvider+Policy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift)
  - la policy interna ora esplicita che non si deve passare a provider-native fork quando `subagent_*` è già disponibile.

## Copertura aggiunta/aggiornata

- [ToolEnabledLLMProviderSubagentPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests.swift)
- [CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift)
- smoke su [MCPSubagentRoutingTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/MCPSubagentRoutingTests.swift)

## Verifica eseguita

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests`
  - `CoderEngineTests/MCPSubagentRoutingTests`
  - `SoloCodeAppTests/CLIProfileProvisionerInstructionSyncSubagentRoutingTests`
  -> verde
