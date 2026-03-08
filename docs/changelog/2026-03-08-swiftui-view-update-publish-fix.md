# 2026-03-08 - Fix publish store durante update view SwiftUI

- Documentato il bug in [P1-2026-03-08-swiftui-publish-during-view-update.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-08-swiftui-publish-during-view-update.md).
- Aggiornato [TaskActivityStore+Query.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift) per evitare che `swarmCardStates(for:)` aggiorni cache osservate mentre viene letto dal `body` SwiftUI.
- Aggiornato [TaskActivityStore+Swarm.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Swarm.swift) con una snapshot side-effect free delle swarm cards ordinabili.
- Aggiornato [AccountUsageDashboardStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/AccountUsageDashboardStore.swift) per differire di un tick l'avvio del refresh osservato dalla UI.
- Aggiornato [ProviderUsageStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Settings/ProviderUsageStore.swift) per differire i publish iniziali dei refresh Codex, Claude e Gemini fuori dal turno di update corrente.
- Aggiornato [CodeReviewPanelStore+ActionOutput.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift) per inoltrare envelope e task activity review nel tick successivo del main actor.
- Estesi [TaskActivityStoreSwarmCardsTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift) con una regressione che verifica che la lettura di `swarmCardStates()` non emetta publish osservabili dalla view.
