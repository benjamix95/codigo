# 2026-03-20 — Thread Provider Selection Rust Tranche

## Modifiche
- aggiunto il contratto shared [thread_provider_selection.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/thread_provider_selection.rs)
- aggiunta la policy Rust [thread_selection.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/thread_selection.rs)
- esposta la FFI `chat_core_thread_provider_selection` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- la facciata `ThreadProviderSelectionService` e' stata assorbita in [RustMainChatProviderFactory.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift), che e' gia' allowlisted come bridge Swift del dominio provider Rust
- aggiornata la copertura in [ThreadProviderSelectionServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift) e [app_core_boundary_main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/app_core_boundary_main_chat.rs)

## Risultato
- passano a Rust:
  - `effectiveMode` del thread
  - provider resolution per `agent` / `ide` / `plan` / `debug` / `browser` / `mcpServer`
  - validazione del bound provider mancante
- resta in Swift:
  - `persistRuntimeProviderSelection` come mutazione locale del `ChatStore`

## Progress
- `% capability totale`: `~8%`
- `% capability main-chat`: `~88%`
- `% strutturale totale`: `~1.2%` (`16 / 1310`)
- `% strutturale main-chat`: `~3.5%` (`7 / 198`)
