## 2026-03-21

## Logica migrata in Rust
- aggiunto il nuovo request/response runtime in [main_chat_runtime.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_runtime.rs) per il path `chat_core_runtime_poll_provider`
- introdotto il modulo Rust [runtime_provider_poll.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/runtime_provider_poll.rs) che esegue:
  - poll della sessione provider
  - drain ordinato degli eventi
  - riduzione del `runtimeSnapshot`
  - restituzione di `uiEvents` render-ready a Swift
- esportato il nuovo boundary in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs) e [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/mod.rs)
- aggiornato [RustMainChatProviderAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift), [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift) e [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift) per usare il nuovo boundary e togliere a Swift `runtimeEventKind/runtimePayload`

## Riduzione strutturale richiesta dal gate
- assorbito [DebugNativePipelineModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineModels.swift) dentro [DebugNativePipelineExecutor.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineExecutor.swift) e rimosso dal progetto Xcode
- assorbito [ChatPanelView+PartA_ComposerFocus.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+PartA_ComposerFocus.swift) dentro [ChatPanelView+DisplayFlags.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+DisplayFlags.swift) e rimosso dal progetto Xcode

## Test
- aggiornati [ConversationFlowCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift) con coverage del path Rust-specialized
- mantenuti verdi i test del provider adapter Rust e delle sessioni provider Rust
- smoke test sui path runtime strutturali con [WorkspaceStorePathNormalizationTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/WorkspaceStorePathNormalizationTests.swift)

## Validazione
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::session_tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/WorkspaceStorePathNormalizationTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files \"Native/AppCoreProtocol/src/main_chat_runtime.rs,Native/RustCore/src/main_chat/runtime_provider_poll.rs,Native/RustCore/src/main_chat/mod.rs,Native/RustCore/src/ffi/main_chat.rs,App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift,App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift,App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineExecutor.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/Native/DebugNativePipelineModels.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+DisplayFlags.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+PartA_ComposerFocus.swift,Solo Code.xcodeproj/project.pbxproj,Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift\" --format text`

## Rischio controllato
- questa tranche non sposta ancora in Rust l'intero watchdog del coordinator per i provider non-Rust
- per il path `MainChatRustTransportProvider`, pero', la riduzione del runtime snapshot non e' piu' Swift-owned
