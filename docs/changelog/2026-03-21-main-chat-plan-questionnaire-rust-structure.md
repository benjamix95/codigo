# 2026-03-21 main chat plan questionnaire rust structure

## Summary
- il `plan` espone ora anche il questionario di chiarificazione tipizzato dal boundary Rust
- il panel consuma il dato strutturato prima del fallback markdown parser
- Mermaid resta invariato

## Changes
- `Native/AppCoreProtocol/src/main_chat_runtime.rs`
  - aggiunti `MainChatPlanQuestionnaire`, `MainChatPlanQuestion`, `MainChatPlanQuestionOption`
  - `MainChatPlanSnapshot` ora include `clarificationQuestionnaire`
- `Native/AppCoreProtocol/src/main_chat_ui.rs`
  - `MainChatUiPlanSnapshot` ora include `clarificationQuestionnaire`
- `Native/RustCore/src/main_chat/plan_markdown.rs`
  - aggiunto parser Rust del questionario strutturato da blocchi `## Questions`
- `Native/RustCore/src/main_chat/plan_runtime.rs`
  - popola `clarificationQuestionnaire` nelle transizioni questioning/clarification
- `Native/RustCore/src/main_chat/plan_ui_flow.rs`
  - `plan_receive_clarification_questions` popola il questionario strutturato
- `Native/RustCore/src/main_chat/ui_projection.rs`
  - la projection UI passa il questionario strutturato allo snapshot del panel
- `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatStoreBridgeModels.swift`
  - bridge Swift aggiornati con il nuovo campo strutturato
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_SidebarsAndSwarm.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartO_PlanPromptBuilders.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift`
  - il panel usa `clarificationQuestionnaire` se presente e torna al parser markdown solo come fallback
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessage.swift`
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartJ_PlanChoice.swift`
  - ripuliti i reset dello stato questionario durante cambio fase/error path
- `Tests/SoloCodeAppTests/RustMainChatUIBoundaryPlanTests.swift`
- `Tests/SoloCodeAppTests/PlanPanelVisualSmokeTests.swift`
  - test aggiornati al nuovo contratto del panel
- `docs/bugs/P2-2026-03-21-plan-clarification-questionnaire-still-lived-in-swift-ui-parser.md`
  - registrato il residuo eliminato in questa tranche

## Validation
- `cargo test -p solocode_rust_core --quiet`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/PlanPanelVisualSmokeTests -only-testing:SoloCodeAppTests/PlanOptionsParserTests`
