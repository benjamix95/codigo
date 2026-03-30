# Changelog — 2026-03-30 — Subagent native lifecycle e pannello context

## Cosa ho corretto

- Il launch ack dei `coderide_subagent_*` non viene più trattato come `completed` reale.
- Codex app-server non sintetizza più un card terminale quando riceve solo `OK — subagent ... launched`.
- Il parser Swift Codex CLI continua a tenere il trace MCP tecnico, ma non genera più lifecycle sintetici terminali dai launch ack.
- Claude e Codex vengono istruiti a preferire il lifecycle nativo dei sub agent/task e a non usare `coderide_subagent_*` come proxy del child lifecycle in main chat.
- Il pannello sub agent mostra ora un descrittore esplicito di contesto dedicato/read-only, con `thread_id` o `task_id` quando il provider lo espone.

## File principali

- Runtime/provider:
  - [codex_app_server.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs)
  - [codex_app_server_subagent_lifecycle.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server_subagent_lifecycle.rs)
  - [codex_app_server_prompt.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server_prompt.rs)
  - [claude.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/claude.rs)
  - [CodexCLIProvider+SyntheticEvents.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/StreamSupport/CodexCLIProvider+SyntheticEvents.swift)
- UI/panel:
  - [SubagentLaunchAcknowledgement.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Support/SubagentLaunchAcknowledgement.swift)
  - [SubagentContextDescriptor.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Support/SubagentContextDescriptor.swift)
  - [SwarmLiveReducer+Lifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/SwarmLiveReducer+Lifecycle.swift)
  - [SwarmLiveReducer+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/SwarmLiveReducer+Helpers.swift)
  - [SwarmLiveTypes.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/SwarmLiveTypes.swift)
  - [SubagentChatView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatView.swift)

## Copertura aggiunta

- Parser Codex CLI:
  - [CodexCLIProviderStreamParsingTests+SubagentLaunchAck.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodexCLI/CodexCLIProviderStreamParsingTests+SubagentLaunchAck.swift)
- Reducer/transcript/context:
  - [SwarmLiveReducerTests+SubagentLaunchAck.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SwarmLiveReducerTests+SubagentLaunchAck.swift)
  - [SubagentChatTranscriptTests+SubagentLaunchAck.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SubagentChatTranscriptTests+SubagentLaunchAck.swift)
  - [SubagentContextDescriptorTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SubagentContextDescriptorTests.swift)
  - [CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests+SubagentRouting.swift)

## Verifiche eseguite

- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet` -> 340 test verdi
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'` con selezione:
  - `CoderEngineTests/CodexCLIProviderStreamParsingTests`
  - `CoderEngineTests/CodexCLIProviderRealisticSequenceTests`
  - `CoderEngineTests/CodexAppServerMCPWireIntegrationTests`
  - `SoloCodeAppTests/SwarmLiveReducerTests`
  - `SoloCodeAppTests/SwarmLiveReducerSubagentLaunchAckTests`
  - `SoloCodeAppTests/SubagentChatTranscriptTests`
  - `SoloCodeAppTests/SubagentChatTranscriptLaunchAckTests`
  - `SoloCodeAppTests/SubagentChatSegmentBuilderTests`
  - `SoloCodeAppTests/SubagentContextDescriptorTests`
  - `SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests`
  - `SoloCodeAppTests/CLIProfileProvisionerInstructionSyncSubagentRoutingTests`
  -> verde
