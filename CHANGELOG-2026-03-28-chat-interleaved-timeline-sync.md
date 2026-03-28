# Changelog - 2026-03-28 - Chat interleaved timeline sync

- Corretto il path `sync_assistant_pipeline_state` che poteva ricollassare la timeline assistant in un blocco monolitico dopo il round-trip Swift/Rust.
- Il merge Rust dei blocchi timeline ora preserva i blocchi core interleavati `primaryText/toolMarker/primaryText` invece di deduplicare i `primaryText` per solo `kind`.
- La normalizzazione Rust non sovrascrive più il primo `primaryText` con il testo aggregato quando il messaggio contiene già più segmenti `primaryText`.
- Rinforzata la preferenza locale Swift per i blocchi pipeline con struttura narrativa più ricca, non solo con più marker o più blocchi totali.
- Aggiunte regressioni:
  - Rust: preservazione dei blocchi interleavati nel merge store.
  - App: persistenza del layout `text/tool/text` dopo `updateAssistantMessagePipelineState`.
  - App: policy Swift che preferisce la timeline pipeline più ricca.
- File toccati:
  - `Native/RustCore/src/main_chat/store/messages/assistant.rs`
  - `Native/RustCore/src/main_chat/store/messages/helpers.rs`
  - `Native/RustCore/src/main_chat/store/tests/messages.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+PipelineStateLocalSync.swift`
  - `Tests/SoloCodeAppTests/ChatStorePipelineInterleavingPersistenceTests.swift`
