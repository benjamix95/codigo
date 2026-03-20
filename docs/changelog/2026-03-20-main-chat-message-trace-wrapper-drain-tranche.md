# Changelog - 2026-03-20 - Main Chat Message Trace Wrapper Drain Tranche

## Obiettivo
- Ridurre il debito strutturale del prefisso `Chat` assorbendo wrapper di presentazione sottili e un file legacy del cluster `MessageToolTrace`.

## Modifiche principali
- `MessageToolTraceView+Header.swift` rimosso:
  - header, collapse shortcut, hidden events button e titolo collassato sono stati assorbiti in `MessageToolTraceView.swift`
- `PrimaryTextBlockView.swift` rimosso:
  - il primary text viene renderizzato direttamente in `ChatTurnView.swift`
- `TraceSummaryCardView.swift` rimosso:
  - il trace summary viene renderizzato direttamente in `ChatTurnView.swift`

## Riduzione strutturale
- Rimossi tre file legacy reali dal prefisso `Chat`:
  - `App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Header.swift`
  - `App/SoloCodeApp/Sources/Chat/Timeline/Blocks/PrimaryTextBlockView.swift`
  - `App/SoloCodeApp/Sources/Chat/Timeline/Blocks/TraceSummaryCardView.swift`

## Test eseguiti
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit ...`

## Esito tranche
- `Legacy hard-fail attivi` nel prefisso `Chat`: `83`
- `Legacy oltre budget nel tranche gate`: `0`
- Il render assistant/trace è meno frammentato e più vicino ai consumer reali senza cambiare il comportamento osservabile.
