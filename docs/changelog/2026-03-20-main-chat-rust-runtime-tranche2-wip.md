# 2026-03-20 — Tranche 2 `main chat` runtime Rust completata

## Modifiche
- esteso il protocollo shared con [main_chat_runtime.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_runtime.rs) per snapshot runtime `direct_stream` e `plan`
- aggiunti i moduli Rust:
  - [state.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/state.rs)
  - [stream_runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/stream_runtime.rs)
  - [continuation.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/continuation.rs)
  - [plan_prompts.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/plan_prompts.rs)
  - [plan_runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/plan_runtime.rs)
- aggiornato [runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/runtime.rs) e [ffi/main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs) per gestire `chat_core_handle_action` sul runtime snapshot completo
- collegato Swift al nuovo runtime Rust:
  - [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift)
  - [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift)
  - [ChatPipelineEvent.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineEvent.swift)
  - [ChatPanelView+PartN_Continuation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartN_Continuation.swift)
  - [ChatPanelView+PartO_PlanPromptBuilders.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartO_PlanPromptBuilders.swift)
  - [ChatPanelView+PartM_MultiTurn.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartM_MultiTurn.swift)
  - [ChatPanelView+PartN_PlanPrompts.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartN_PlanPrompts.swift)
  - [ChatPanelView+PartM_Phase3.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartM_Phase3.swift)
- mantenuto il fallback Swift dove il bridge Rust non restituisce snapshot validi, per containment del rischio

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `xcodebuild build -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - build verde
- `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "$(git diff --name-only --diff-filter=ACMR | paste -sd, -)" --format text`
  - gate strutturale verde sul diff reale
- `xcodebuild build-for-testing -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - verde
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
  - verde

## Stato
- `% capability`: **40%**
- `% strutturale`: **2.7%** sul denominatore completo `main-chat` (`72` legacy hard-fail residui su `74` del baseline espanso)
- `% strutturale sul diff reale della tranche`: gate verde, `legacy oltre budget nel tranche gate: 0`
