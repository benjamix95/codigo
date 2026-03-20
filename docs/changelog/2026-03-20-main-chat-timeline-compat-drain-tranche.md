# Changelog - 2026-03-20 - Main Chat Timeline Compat Drain Tranche

## Obiettivo
- Ridurre ancora l’ownership Swift residua nel dominio `main chat` drenando il bridge pipeline compat dal path standard e consolidando il render timeline.

## Modifiche principali
- `ChatTimelineView.swift` rimosso:
  - il dispatch user/assistant è stato assorbito in `ChatPanelView+PartD_MessagesScroll.swift`
- `ChatPanelView+PipelineChat.swift` rimosso:
  - il bridge compat è stato spostato in `PipelineLegacyChatAdapter.swift`
  - il path standard non dipende più dal vecchio file `PipelineChat`
- `PartD_MessagesScroll.swift` non usa più `currentAssistantPipelineTarget(for:)` per il path standard del todo card
- Aggiunta regression coverage in `ChatTodoVisibilityTests` per il fallback senza target pipeline

## Riduzione strutturale
- Rimossi due file legacy reali dal prefisso `Chat`:
  - `App/SoloCodeApp/Sources/Chat/Timeline/ChatTimelineView.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift`

## Test eseguiti
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit ...`

## Esito tranche
- `Legacy hard-fail attivi` nel prefisso `Chat`: `84`
- `Legacy oltre budget nel tranche gate`: `0`
- Il path standard `direct-stream` non dipende più dal vecchio wrapper timeline né dal vecchio file `ChatPanelView+PipelineChat.swift`.
