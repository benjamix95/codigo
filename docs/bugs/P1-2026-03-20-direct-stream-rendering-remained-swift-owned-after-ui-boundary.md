# [P1] Direct-stream standard continuava a renderizzare da mutazioni Swift locali dopo il boundary UI Rust

## Priorita'
- P1

## Area
- Main Chat
- direct stream
- Rust cutover

## Sintomo
- Il batch precedente aveva introdotto `main_chat_ui`, ma il path standard della main chat continuava a usare callback Swift per:
  - replacement del testo assistant
  - merge reasoning live
  - throttling/flush del contenuto stream
  - finalizzazione locale del turno

## Impatto
- Rischio di divergenza tra `runtime_snapshot` Rust e messaggio effettivamente renderizzato.
- Duplice ownership del live state: Rust per il runtime, Swift per il rendering immediato.
- Cutover incompleto del ramo standard `direct-stream`.

## Fix applicato in questo batch
- I callback `onText`, `onRaw`, `onError` del ramo standard passano ora dal boundary `main_chat_ui`.
- I raw event rilevanti per la UI vengono ridotti nel runtime Rust.
- Lo store snapshot renderabile viene sincronizzato in Rust e poi applicato alla shell Swift.
- Rimosso il file legacy `ChatPanelView+PartQ_StreamCommit.swift`.

## Test di regressione
- Rust:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- Swift:
  - `SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `SoloCodeAppTests/ConversationFlowCoordinatorTests`

## Follow-up
- Ridurre ancora `handleRawStreamEvent(...)` ai soli side effect non visuali.
- Drenare il path `PartR_Tail` e la finalizzazione stream verso snapshot/UI intent Rust-only.
