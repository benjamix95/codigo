# Changelog — 2026-03-27 — Remediation round 2 su Plan / Chat / Todo

## Cosa e' stato fatto

- Corretta la doppia ownership dei side effect raw nei job pipeline.
- Sistemato il restore del `PlanFlow` per la build-agent conversation.
- Rimosso il doppio sync del plan panel verso il bridge Rust.
- Resa scope-first la query delle activity plan recenti.
- Alleggerito il path caldo del `ToolTraceStore` con append ordinato e buffering su `diskQueue`.

## File principali toccati

- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlowHelpers.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+ScopedQueries.swift`
- `App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift`
- `App/SoloCodeApp/Sources/Tasking/ToolTraceStore+DiskWrites.swift`

## Test eseguiti

- `xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests -only-testing:SoloCodeAppTests/ToolTraceStoreTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests`

## Esito

- suite mirata verde sui fix funzionali del secondo giro
- aggiunti test di regressione su:
  - ownership raw callback vs side effect locale
  - restore `.building` del build-agent
  - plan trace scope-first
