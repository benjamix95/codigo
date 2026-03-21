# 2026-03-21 main chat plan rust cutover proposal/build structure

## Summary
- il boundary Rust del `plan` ora emette snapshot strutturati per proposal/choice/build invece di lasciare a Swift parsing e classificazione dell'output finale
- nessuna modifica al comportamento Mermaid: nessun intervento su parsing, rendering o propagation dei blocchi `mermaid`

## Changes
- `Native/AppCoreProtocol/src/main_chat_runtime.rs`
  - aggiunti a `MainChatPlanSnapshot` i campi strutturati `summaryTitle`, `chosenPath`, `optionTitles`, `canonicalTodos`
- `Native/AppCoreProtocol/src/main_chat_ui.rs`
  - estesi gli snapshot UI del `plan` con gli stessi campi strutturati per evitare reinterpretazioni Swift
- `Native/RustCore/src/main_chat/plan_markdown.rs`
  - nuovo parser Rust per decisioni `plan`: screening markers, `NO_QUESTIONS_NEEDED`, option parsing, todo extraction, summary title
- `Native/RustCore/src/main_chat/plan_runtime.rs`
  - `plan_apply_generation_result` ora costruisce proposal strutturate in Rust
  - introdotta l'azione `plan_choose_option` per validare la scelta e derivare i canonical todos in Rust
- `Native/RustCore/src/main_chat/ui_projection.rs`
  - la projection del `plan` usa i campi strutturati Rust per `chosenPath`, titoli opzione, todo canonici e summary
- `Native/RustCore/src/main_chat/ui_intents.rs`
  - `choose_plan_option` ora fallisce se l'opzione non contiene una checklist valida
  - sincronizzazione del `PlanBoard` da snapshot Rust invece di ricostruzione Swift ad hoc
- `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatStoreBridgeModels.swift`
  - aggiornati i bridge Swift con il nuovo contratto dati del `plan`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurn.swift`
  - rimossi fallback Swift su screening/question summary, ora usa `chatContentOverride` Rust
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift`
  - rimossa la validazione TODO/opzioni in Swift
  - proposal recap, `PlanBoard` e history entry derivano dai campi strutturati Rust
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartK_PlanExecution.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartJ_PlanChoice.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+BuildBar.swift`
  - la build non parsea piu' direttamente il markdown per verificare la checklist; usa la scelta gia' validata dal boundary Rust
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartR_Tail.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - rimosso il classifier Swift dal runtime path di finalizzazione stream
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - allowlist esplicita dei file rimasti come glue/UI policy dopo il taglio della logica decisionale
- `Native/AppCoreRust/tests/app_core_boundary_main_chat.rs`
  - aggiornato il boundary test per riflettere il nuovo confine allowlisted
- `Tests/SoloCodeAppTests/RustMainChatUIBoundaryPlanTests.swift`
  - aggiornato al nuovo snapshot Rust strutturato
- `docs/bugs/P1-2026-03-21-plan-runtime-still-relied-on-swift-classification-and-build-parsing.md`
  - registrato il bug di ownership residua nel runtime `plan`

## Validation
- `cargo test -p solocode_rust_core --quiet`
- `cargo test -p app_core_rust --quiet`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/PlanQuestionPhaseDecisionTests -only-testing:SoloCodeAppTests/PlanOutputClassifierTests`
- `cargo run -p app_core_rust --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist /Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt --candidate-files 'App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurn.swift,App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift,App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartN_PlanPrompts.swift,App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartO_PlanPromptBuilders.swift,App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift,App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanQuestionnaire.swift,App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartR_Tail.swift,App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift,App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift,App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift,App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift' --fail-on-legacy-non-ui --format json`
