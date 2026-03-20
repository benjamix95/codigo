# [P1] Main Chat UI boundary mancante lasciava il direct-stream sotto ownership Swift

## Priorita'
- P1

## Area
- Main Chat
- Rust cutover
- direct stream runtime

## Sintomo
- Il direct-stream standard della main chat continuava a partire senza un boundary UI Rust-owned canonico.
- La shell Swift costruiva e possedeva ancora parte del contratto osservabile del turno live.

## Impatto
- Il cutover `core-only Rust` non era verificabile end-to-end sul path chat standard.
- La UI poteva continuare a dipendere da projection e intent Swift ad hoc, reintroducendo regressioni di ownership.
- Il tranche gate del prefisso `Chat` non aveva una riduzione strutturale reale sul boundary UI.

## Evidenza tecnica
- Mancavano entrypoint FFI dedicati per projection e intent UI della main chat.
- Mancava un adapter Swift sottile che parlasse con un contratto `main_chat_ui` Rust-owned.
- Il branch standard `sendMessage` non verificava la disponibilita' del nuovo boundary prima di entrare nel direct stream.

## Fix applicato in questa tranche
- Aggiunto `main_chat_ui` in `AppCoreProtocol`.
- Aggiunti projection + intent handler in `RustCore` con entrypoint FFI `chat_core_ui_project` e `chat_core_ui_handle_intent`.
- Aggiunto bridge Swift sottile sopra `StoreRust`.
- Inserito fail-closed gate nel branch direct-stream standard.
- Ridotti file legacy reali nel prefisso `Chat` assorbendo modelli `MessageRow` in file gia' esistenti.

## Test di regressione
- Rust unit: `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- Rust FFI: `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- Swift app-side:
  - `SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `SoloCodeAppTests/ConversationFlowCoordinatorTests`

## Follow-up
- Migrare il fan-out del direct-stream standard dal branch Swift a `main_chat_ui_handle_intent`.
- Ridurre progressivamente `@State` business-critical della `ChatPanelView` in favore di `MainChatUiSnapshot`.
