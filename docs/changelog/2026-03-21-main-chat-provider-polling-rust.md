## 2026-03-21

## Modifiche
- aggiunto il request `MainChatProviderSessionPollRequest` in [main_chat_provider.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_provider.rs)
- aggiunto il nuovo boundary FFI `chat_core_provider_poll` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- implementato il polling bloccante della sessione provider in [session.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/session.rs), in modo che l'attesa eventi/terminal snapshot non viva piu' nel loop Swift
- aggiornato [RustMainChatProviderAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift) per usare `chat_core_provider_poll` al posto del ciclo `resume + Task.sleep`
- assorbito [ChatPanelView+PartL_SendMessageAutoReview.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessageAutoReview.swift) in [ChatPanelView+PartL_PromptOptimization.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_PromptOptimization.swift) e rimosso dal progetto Xcode per ridurre di 1 il backlog legacy `Chat`

## Test
- aggiunto un test Rust in [session_tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/session_tests.rs) per il polling di una sessione che termina senza nuovi eventi
- aggiunti test app-side in [RustMainChatProviderFactoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift) per:
  - completamento del provider transport da snapshot terminale `completed`
  - failure del provider transport da snapshot terminale `failed`

## Validazione
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::cli::process::tests -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::session_tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift,App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessage.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessageAutoReview.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_PromptOptimization.swift,Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift" --format text`

## Rischio controllato
- nessun cambio a `ConversationFlowCoordinator.runStream(...)` in questa tranche
- Swift continua a fare solo dispatch dei callback, ma non possiede piu' il polling `resume/sleep` del transport Rust
