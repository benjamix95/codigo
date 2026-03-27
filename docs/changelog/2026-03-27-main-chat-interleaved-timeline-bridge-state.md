# 2026-03-27 — Main Chat Interleaved Timeline Bridge State

## Summary

- corretto il bug per cui la main chat perdeva la timeline interleavata `text/tool/text` tra reducer Swift, restore da store e boundary Rust
- eliminato il path che faceva ricadere troppo spesso il renderer nel fallback `single monolithic text`

## Changes

- aggiornato [ChatTurnState.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/ChatTurnState.swift)
  - aggiunti `textSegments`, `timelineSegments`, `timelineNextSequence`
  - `blocks` ora emette piu' `primaryText` e `toolMarker` quando la timeline e' disponibile
- aggiornato [ChatPipelineReducer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/ChatPipelineReducer.swift)
  - il reducer Swift ora segmenta testo, reasoning e tool use come il reducer Rust
- aggiornato [ChatPipelineEvent.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/ChatPipelineEvent.swift)
  - `MainChatBridgeState` ora round-trippa i campi timeline senza perderli
  - aggiunti default sicuri per le call site legacy del bridge
- aggiornato [PipelineLegacyChatAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters/PipelineLegacyChatAdapter.swift)
  - il restore da `ChatStore` ricostruisce la timeline interleavata da `resolvedTimelineBlocks`
- aggiornato [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift)
  - inizializzazione esplicita del bridge allineata ai nuovi campi timeline
- aggiunto [ChatPipelineTimelineStateTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPipelineTimelineStateTests.swift)
  - regressione su segmentazione `text/tool/text`
  - round-trip bridge JSON dei campi timeline

## Validation

- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::reducer -- --nocapture`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::ui_state_sync -- --nocapture`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineTimelineStateTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/ChatTimelineInterleavingTests`
