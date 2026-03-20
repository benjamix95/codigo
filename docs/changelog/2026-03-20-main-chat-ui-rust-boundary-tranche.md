# Changelog - 2026-03-20 - Main Chat UI Rust Boundary Tranche

## Obiettivo
- Introdurre il primo boundary UI Rust-owned della main chat senza riscrivere in blocco la shell SwiftUI.

## Modifiche principali
- Aggiunto `Native/AppCoreProtocol/src/main_chat_ui.rs` con:
  - `MainChatUiState`
  - `MainChatUiSnapshot`
  - `MainChatUiProjectRequest/Response`
  - `MainChatUiIntentRequest/Response`
- Esteso `Native/RustCore/src/main_chat/**` con:
  - projection UI canonica
  - intent handler UI
  - export dal modulo `main_chat`
- Aggiunti entrypoint FFI:
  - `chat_core_ui_project`
  - `chat_core_ui_handle_intent`
- Esteso il bridge Swift `StoreRust` con:
  - DTO `MainChatUI*Bridge`
  - helper `uiState(...)`
  - `projectUI(...)`
  - `handleUIIntent(...)`
- Inserito un controllo fail-closed nel branch direct-stream standard di `ChatPanelView+PartL_SendMessageExecution.swift`:
  - se la projection UI Rust non e' disponibile, il turno non parte.

## Riduzione strutturale legacy
- Assorbito `App/SoloCodeApp/Sources/Chat/MessageRow/MessageRowModels.swift` in `MessageRow+Thinking.swift`.
- Assorbito `App/SoloCodeApp/Sources/Chat/MessageRow/MessageRow+ThinkingBlocks.swift` in `MessageRow+Thinking.swift`.
- Rimossi due file legacy dal prefisso `App/SoloCodeApp/Sources/Chat`.

## Allowlist aggiornata
- Riclassificati alcuni file puramente UI / presentation helper in `Chat` per riflettere ownership reale:
  - `ClickableMessageContent.swift`
  - `MessageRow.swift`
  - `MessageRow+Indicators.swift`
  - vari file `TaskStatus`
  - vari file `Timeline/Blocks` e `Timeline`
  - `ChatPipelineEvent.swift` come binding adapter

## Test eseguiti
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_markers`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit ...`

## Esito tranche
- Boundary UI Rust-owned introdotto e validato.
- Prefisso `Chat` ridotto strutturalmente rispetto a `HEAD`.
- Tranche gate `rust_cutover_boundary` passato sui file toccati.
