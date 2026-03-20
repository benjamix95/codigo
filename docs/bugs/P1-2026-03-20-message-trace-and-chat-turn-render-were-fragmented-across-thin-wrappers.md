# [P1] Message trace e chat turn erano frammentati in wrapper di presentazione sottili

## Priorita'
- P1

## Area
- Main Chat
- MessageToolTrace
- timeline render

## Sintomo
- Il cluster `MessageToolTrace` manteneva un file legacy dedicato solo all’header della root view.
- `ChatTurnView` delegava ancora a wrapper sottili per il primary text e il trace summary, senza reale ownership separata.

## Impatto
- Debito strutturale nel prefisso `Chat` più alto del necessario.
- Più file e più indirection nel render della timeline senza beneficio di separazione di dominio.
- Maggior rischio di micro-regressioni di layout dovute a wrapper pass-through.

## Fix applicato in questa tranche
- `MessageToolTraceView+Header.swift` è stato assorbito in `MessageToolTraceView.swift`.
- `PrimaryTextBlockView.swift` e `TraceSummaryCardView.swift` sono stati assorbiti in `ChatTurnView.swift`.
- Rimossi tre file legacy reali dal prefisso `Chat`.

## Test di regressione
- Rust:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- Swift:
  - `SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `SoloCodeAppTests/RustMainChatUIBoundaryTests`
  - `SoloCodeAppTests/ConversationFlowCoordinatorTests`
  - `SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests`

## Follow-up
- Valutare una tranche dedicata al restante cluster `MessageToolTraceView+State/Helpers/Details/*` solo se si può rimuovere almeno un file senza rompere seam condivise.
