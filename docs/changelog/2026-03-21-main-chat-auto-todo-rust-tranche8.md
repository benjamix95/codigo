# 2026-03-21 — Main Chat AutoTodo Rust Tranche 8

## Modifiche
- esteso [main_chat_ui.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_ui.rs) con:
  - stato effimero `autoTodoRuntimeStateByMessage`
  - DTO `MainChatUiTodoPatch`
  - enum `MainChatUiTodoMutation`
  - `todoPatches` nella response intent
- aggiunti i moduli Rust:
  - [auto_todo.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/auto_todo.rs)
  - [auto_todo_support.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/auto_todo_support.rs)
- esteso [ui_intents.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_intents.rs) con:
  - `auto_todo_begin_runtime`
  - `auto_todo_record_operation`
  - `auto_todo_finalize_runtime`
  - `auto_todo_discard_runtime`
- aggiornati i bridge Swift in:
  - [MainChatStoreBridgeModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatStoreBridgeModels.swift)
  - [RustMainChatStoreAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift)
  - [MainChatTodoPatchAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatTodoPatchAdapter.swift)
- ridotti a thin adapter i call site Swift di AutoTodo in:
  - [ChatPanelView+PartF_AutoTodoRuntime.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_AutoTodoRuntime.swift)
  - [ChatPanelView+PartF_DebugTodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoEvents.swift)
  - [ChatPanelView+PartF_DebugTodoLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoLifecycle.swift)
  - [ChatPanelView+PartE_ToolTraceTurn.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Lifecycle/ChatPanelView+PartE_ToolTraceTurn.swift)
- rimosso il file legacy [ChatPanelSupport+AutoTodo.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+AutoTodo.swift)
- spostati i soli helper di display/todo-card in [ChatPanelView+TodoCardSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+TodoCardSelection.swift)
- aggiunta copertura in:
  - [ui_tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_tests.rs)
  - [main_chat_ui.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/main_chat_ui.rs)
  - [RustMainChatAutoTodoBoundaryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests.swift)

## Risultato
- la shell Swift non compone più policy AutoTodo runtime
- il dominio Rust decide `create / update / finalize / discard` e restituisce patch todo già applicabili
- `TodoStore` resta Swift, ma solo come adapter locale di persistenza/render
- il prefisso `Chat` perde un file legacy reale e scende di un’altra unità nel tranche gate

## Verifiche
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCoreBootstrapPolicyTests`
- `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files ...`
