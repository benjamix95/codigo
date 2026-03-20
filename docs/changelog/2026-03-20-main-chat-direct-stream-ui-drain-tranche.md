# Changelog - 2026-03-20 - Main Chat Direct-Stream UI Drain Tranche

## Obiettivo
- Spostare il rendering live standard della main chat sul boundary `main_chat_ui` gia' introdotto, riducendo la logica Swift locale di stream/finalizzazione.

## Modifiche principali
- Esteso `RustCore` con sync store da `runtime_snapshot`:
  - nuovo file `Native/RustCore/src/main_chat/ui_state_sync.rs`
  - nuovi intent `stream_*` in `ui_intents.rs`
- Esteso `stream_runtime.rs` per ridurre anche raw event UI-rilevanti:
  - `reasoning`
  - `mermaid_render`
  - `command_execution` / `bash`
  - file mutation events
- Il ramo standard in `ChatPanelView+PartL_SendMessageExecution.swift` ora:
  - usa `handleUIIntent(...)` nei callback stream
  - non usa piu' `applyStreamingUpdate(...)`
  - non applica piu' artifact pipeline legacy per il path standard
- `ChatPanelView+PartQ_StreamCommit.swift` e' stato rimosso:
  - `discardPendingStreamingState`, `flushStreamingContent` e sync intent sono confluiti in `PartQ_Finalizers`
  - il walkthrough builder e' stato estratto in `ChatPanelView+PartQ_Walkthrough.swift`
- `PartN_Continuation` mantiene il path plan-specifico senza dipendere dal vecchio stream commit file.

## Riduzione strutturale
- Rimosso un file legacy reale dal ramo stream/finalization:
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartQ_StreamCommit.swift`
- Il tranche gate `Chat` scende a:
  - `Legacy hard-fail attivi: 86`
  - `Legacy oltre budget nel tranche gate: 0`

## Test eseguiti
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit ...`

## Note
- Restano solo side effect non visuali nel path Swift `handleRawStreamEvent(...)` del ramo standard.
- Plan flow, rewind, agent pipeline e debug runtime restano fuori da questa tranche.
