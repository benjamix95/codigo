# [P1] Il tail standard del direct-stream continuava a finalizzare il turno in Swift dopo il cutover live

## Priorita'
- P1

## Area
- Main Chat
- direct stream
- tail finalization

## Sintomo
- Dopo il passaggio del live render al boundary `main_chat_ui`, il ramo standard continuava a finalizzare il turno in Swift.
- Il path di successo in `handleStreamResult(...)` riscriveva ancora contenuto e lifecycle assistant con helper legacy.

## Impatto
- Ownership duplicata del turn finale tra Rust e Swift.
- Rischio di divergenza tra `runtime_snapshot` Rust e stato finale mostrato in chat.
- Il boundary `main_chat_ui` non era ancora l’unico owner del commit terminale standard.

## Fix applicato in questa tranche
- Spostata la finalizzazione standard `success/failure/interrupted` sul boundary Rust `main_chat_ui`.
- Rimosso l’uso standard di `applyLegacyStreamSnapshot(...)` e `applyLegacyLifecycleEvent(...)` nel tail del direct-stream.
- Eliminato il file legacy/orphan `ChatPanelView+.swift`.
- Ridotto il file legacy `ChatPanelView+PartQ_StreamCommit.swift` a zero tramite rimozione completa.

## Test di regressione
- Rust:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- Swift:
  - `SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `SoloCodeAppTests/RustMainChatUIBoundaryTests`
  - `SoloCodeAppTests/ConversationFlowCoordinatorTests`

## Follow-up
- Drenare il fallback `ChatPanelView+PipelineChat.swift` dal path standard, lasciandolo solo per `agent` / compat.
- Valutare un batch dedicato su `PartR_Tail` per spostare anche la derivazione dei summary plan lato build su snapshot Rust-owned dove ha senso.
