# 2026-03-21 — Main Chat Plan UI Rust Tranche 7

## Modifiche
- esteso il contratto shared [main_chat_ui.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_ui.rs) con `questionEpoch` e `isReadyToBuild` per la projection planning
- aggiunto il modulo Rust [plan_ui_flow.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/plan_ui_flow.rs) per gli intent UI del planning
- esteso [ui_intents.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_intents.rs) con:
  - `apply_plan_runtime_action`
  - `plan_receive_clarification_questions`
  - `set_plan_panel_visible`
- aggiornata [ui_projection.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_projection.rs) per proiettare stato planning e panel visibility dal boundary Rust
- sostituito il bridge Swift planning manuale in [ChatPanelView+PartO_PlanPromptBuilders.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartO_PlanPromptBuilders.swift) con chiamate a `main_chat_ui`
- rimosso il file legacy [ChatPanelView+PartN_Continuation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartN_Continuation.swift) e spostata la continuation stream nel thin adapter [ChatPanelView+PlanContinuation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PlanContinuation.swift)
- ridotte le mutazioni planning Swift in:
  - [ChatPanelView+PartJ_PlanChoice.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartJ_PlanChoice.swift)
  - [ChatPanelView+PartB_ComposerUI.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartB_ComposerUI.swift)
  - [ChatPanelView+PartM_MultiTurn.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartM_MultiTurn.swift)
  - [ChatPanelView+PartN_PlanPrompts.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartN_PlanPrompts.swift)
  - [ChatPanelView+PartK_PlanExecution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartK_PlanExecution.swift)
- aggiunta copertura Rust e app-side in:
  - [ui_tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/ui_tests.rs)
  - [main_chat_ui.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/main_chat_ui.rs)
  - [RustMainChatUIBoundaryPlanTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatUIBoundaryPlanTests.swift)
  - [ChatStoreRustBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift)
  - [ReviewCoreBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift)
- aggiunto il defer del loader Rust durante il bootstrap XCTest in [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift), con fallback Swift allineato in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift) e [ChatStoreConversations.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Conversations/ChatStoreConversations.swift)

## Risultato
- la shell Swift non costruisce più a mano `MainChatRuntimeSnapshotBridge` per il planning
- il path planning usa `main_chat_ui` come boundary unico per phase, clarification questions, proposal, choice e panel visibility
- il runtime plan resta puro in Rust, mentre l'orchestrazione UI del planning vive nel nuovo layer `plan_ui_flow`

## Verifiche
- passati:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
  - `cargo build --manifest-path Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
  - `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCoreBootstrapPolicyTests`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanQuestionPhaseDecisionTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files ...`
