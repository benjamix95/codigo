# 2026-03-20 — Main Chat Reasoning Stream Rust Tranche

## Modifiche
- aggiunto il contratto shared [main_chat_reasoning.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_reasoning.rs)
- aggiunto il reducer Rust [reasoning_stream.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/reasoning_stream.rs)
- esposta la FFI `chat_core_reasoning_handle` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- il bridge pubblico `ChatReasoning*` e' stato assorbito in [RustMainChatCLIAccountSnapshots.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatCLIAccountSnapshots.swift), gia' allowlisted nel dominio `Providers/Rust`
- eliminato il file legacy [ChatReasoningStreamReducer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Streaming/ChatReasoningStreamReducer.swift)

## Risultato
- passano a Rust:
  - `isCodexProvider`
  - `presentationMode`
  - `shouldUpdateInlineReasoningState`
  - merge dei blocchi reasoning
  - aggiornamento dei `MessageSegment` reasoning in layout sequenziale

## Progress
- `% capability main-chat`: `~89%`
- `% strutturale main-chat`: `~4.0%` (`8 / 198`)
