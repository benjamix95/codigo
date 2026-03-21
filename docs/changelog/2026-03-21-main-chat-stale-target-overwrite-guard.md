## 2026-03-21

## Modifiche
- reso fail-closed [ui_state_sync.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_state_sync.rs): il sync UI Rust aggiorna la store snapshot solo se trova l'`assistant_message_id` esatto del turno runtime
- irrigidito [PipelineLegacyChatAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters/PipelineLegacyChatAdapter.swift): se esiste un `activeTurn` ma il suo assistant message non è più presente, il binding non ricade più su uno streaming assistant implicito
- aggiornati i fallback di [ChatPanelView+PartQ_Finalizers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift) e [ChatPanelView+PartP_Streaming2.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift) per scrivere solo sul `messageId` risolto del turno attivo tramite `updateAssistantMessage(...)`

## Test
- aggiunto test Rust in [ui_tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_tests.rs) che verifica che `stream_replace_text` con target runtime stale non sovrascriva assistant storici
- aggiunto test app-side in [RustMainChatUIBoundaryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatUIBoundaryTests.swift) sul boundary FFI/UI con `assistant_message_id` mancante
- aggiunto test in [ChatPanelTraceBindingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPanelTraceBindingTests.swift) che blocca il fallback del binding pipeline quando l'`activeTurn` è stale

## Validazione
- da eseguire:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::ui_tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests`

## Rischio controllato
- nessuna modifica al rendering SwiftUI della lista messaggi
- nessun refactor del runtime coordinator o del reducer pipeline
- fix confinato ai guard rail sui target di mutazione, per evitare overwrite della history quando il binding del turno non è affidabile
