# 2026-03-10 — Findings-first review flow con pipeline allargata

## Cosa cambia
- le richieste esplicite di review dalla Home/main chat non avviano più il flusso principale nella chat
- il composer intercetta l’intento review e apre il panel Code Review tramite launch request condivisa
- il panel review usa `Findings` come tab iniziale e default modes `standard + bugFinder + securityAudit`
- `startReview` non forza più la chat come superficie primaria del run
- il tab `Findings` espone una job card con:
  - progress percent
  - fase pipeline
  - gate `verification` e `patch`
  - tools completati/in corso
  - conteggi candidati, verified, published, hidden
- i finding mostrati nel tab `Findings` sono filtrati ai soli elementi `verified + patch preview pronta`
- `VerifiedFindingsStatusService` ora pubblica payload strutturati per pipeline progress:
  - `pipeline_phase`
  - `progress_percent`
  - `steps_total`
  - `steps_completed`
  - `tools_total`
  - `tools_completed`
  - `tools_running`
  - `verification_gate_ready`
  - `patch_gate_ready`
  - `publish_ready`
  - `bundle_modes`
- `MCPSharedBugHunterSnapshot` e `bughunter_status` leggono/esportano anche i nuovi campi di pipeline quando disponibili

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_CodeReviewModes.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessage.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_CodeReviewActions.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Summary.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+GitContext.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingsTab.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingDetail.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunterModels.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`

## Test
- `SoloCodeAppTests/AutoCodeReviewRoutingTests`
- `SoloCodeAppTests/ReviewPanelProviderSelectionTests`
- `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
- `CoderEngineTests/VerifiedFindingsStatusServiceTests`
- `CoderEngineTests/BugHunterHandlerTests`

## Note operative
- per rispettare il vincolo di stabilità del repo, il nuovo comportamento è stato innestato nei file già inclusi nei target Xcode anziché introdurre nuovi file Swift non registrati automaticamente dal progetto
- la chat del review panel resta disponibile come superficie secondaria/manuale, ma non rappresenta più il default flow del run review
