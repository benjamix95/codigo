# [P1] Il render standard della chat era ancora agganciato a un bridge pipeline legacy

## Priorita'
- P1

## Area
- Main Chat
- timeline render
- pipeline compatibility

## Sintomo
- Anche dopo il drenaggio del direct-stream standard, la selected conversation passava ancora da wrapper/render helper legacy per comporre il ramo user/assistant e risolvere il target del todo card.
- Il file `ChatPanelView+PipelineChat.swift` restava nel prefisso `Chat` come bridge di compatibilità più ampio del necessario.

## Impatto
- Ownership Swift più alta del necessario sul path standard.
- Più livelli intermedi del necessario tra store Rust-owned e rendering della timeline.
- Maggior rischio di regressioni da binding assistant target e wrapper UI sottili.

## Fix applicato in questa tranche
- Assorbito `ChatTimelineView.swift` in `ChatPanelView+PartD_MessagesScroll.swift`.
- Rimosso l’uso di `currentAssistantPipelineTarget(for:)` dal path standard di rendering.
- Spostato il bridge legacy da `ChatPanelView+PipelineChat.swift` a `PipelineLegacyChatAdapter.swift` sotto `PipelineProjection/Adapters`.

## Test di regressione
- Rust:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- Swift:
  - `SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `SoloCodeAppTests/RustMainChatUIBoundaryTests`
  - `SoloCodeAppTests/ConversationFlowCoordinatorTests`
  - `SoloCodeAppTests/ChatTodoVisibilityTests`

## Follow-up
- Ridurre ancora `PipelineLegacyChatAdapter.swift` ai soli usi compat `agent` / debug / task-trace.
- Valutare una tranche dedicata ai file `MessageToolTraceView*` rimasti legacy nel prefisso `Chat`.
