# Changelog — 2026-03-27 — Remediation round 3 su PlanPanel history / pending trace

## Cosa e' stato fatto

- Hardening del path `history -> readyToBuild` nel `PlanPanel`.
- Selezione history e opzioni history ora propagano al parent un booleano di buildability reale.
- La trace plan scoped usa anche le `pendingActivities`, cosi' il panel vede il live trace prima del flush definitivo.

## File principali toccati

- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Policy.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistoryHelpers.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+HistorySection.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_SidebarsAndSwarm.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+ScopedQueries.swift`

## Test aggiornati

- `Tests/SoloCodeAppTests/ChatPanelBuildBehaviorTests.swift`
- `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
- `Tests/SoloCodeAppTests/PlanPanelVisualSmokeTests.swift`

## Esito

- fix applicato in modo confinato
- nessuna modifica al resto del worktree locale non correlato
