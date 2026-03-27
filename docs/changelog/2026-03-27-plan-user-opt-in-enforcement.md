# 2026-03-27 — Enforce opt-in esplicito per Plan mode

## Obiettivo

Allineare `plan mode` al comportamento gia' imposto per `debug` e `code review`: nessuna attivazione automatica senza toggle utente.

## Modifiche

- Aggiornato [PromptToolsPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift) per vietare esplicitamente l'auto-attivazione di `activate_plan_mode` e l'uso di alias/keyword come forma implicita di consenso.
- Rimossi gli alias che mappavano `ask_user_question`, `enter_plan_mode` e `exit_plan_mode` su `activate_plan_mode` in:
  - [ProviderToolEventMapper+Normalization.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Normalization.swift)
  - [CoderIDECanonicalToolRegistry+Generated.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift)
  - [canonical_tool_registry.json](/Users/benjaminstoica/SoloCode/Config/tooling/canonical_tool_registry.json)
- Aggiornato [ChatPanelView+PartG_AutoActivation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_AutoActivation.swift) per ignorare `activate_plan_mode` se il toggle plan non e' gia' stato abilitato dall'utente.
- Aggiunto [PlanUserOptInPolicy.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/PlanUserOptInPolicy.swift) come helper dedicato al gate di consenso esplicito per il plan.
- Aggiornati gli helper plan del composer per eliminare trigger impliciti:
  - [ChatPanelSupport+ComposerPlanHelpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+ComposerPlanHelpers.swift)
  - [ChatPanelSupport+PlanFlow.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlow.swift)
  - [ChatPanelView+ShellProperties.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+ShellProperties.swift)
  - [ChatPanelView+PartL_SendMessage.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessage.swift)
  - [ChatPanelView+PartJ_PlanChoice.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartJ_PlanChoice.swift)
- Reso fail-closed l'auto-open del panel quando la sorgente e' `.automaticFlow` e il toggle utente e' spento in:
  - [PlanPanelPresentationSource.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Planning/PlanPanelPresentationSource.swift)
  - [ChatPanelView+PartB_ComposerUI.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift)
  - [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift)
  - [ChatPanelView+PartM_MultiTurnPlanFlowPhase2.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase2.swift)
  - [ChatPanelView+PartM_MultiTurnContinuation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnContinuation.swift)
  - [ChatPanelView+PartN_PlanPrompts.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartN_PlanPrompts.swift)
  - [ChatPanelView+PartM_Phase3.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift)
  - [ChatPanelView+PartR_Tail.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartR_Tail.swift)
  - [ChatPanelView+PartF_DebugTodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents.swift)
- Aggiornato [ChatPanelView+PartN_RuntimeProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift) per non usare piu' il bypass `forcePlanInline` come criterio sufficiente per entrare nel provider plan.

## Verifica

- Aggiornati test in:
  - [ProviderToolEventMapperTests+Search.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ProviderToolEventMapper/ProviderToolEventMapperTests+Search.swift)
  - [PlanPanelHistoryVisibilityTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PlanPanelHistoryVisibilityTests.swift)
  - [PlanShortcutAndCommandTests+CommandParsing.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PlanShortcutAndCommand/PlanShortcutAndCommandTests+CommandParsing.swift)
  - [PlanShortcutAndCommandTests+PolicyAndStreaming.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PlanShortcutAndCommand/PlanShortcutAndCommandTests+PolicyAndStreaming.swift)
