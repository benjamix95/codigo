# Bugfix Record — 2026-03-29

## Scope
- Spostare il footer `Task completed` fuori dalla chrome alta e chiudere la sezione messaggi.
- Impedire a card subagent live/snapshot di apparire sotto l'ultimo testo finale dell'assistente.

## Modifiche
- Aggiunta policy [`ChatFinalActionsPlacementPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatFinalActionsPlacementPolicy.swift) e spostato il rendering del footer finale sotto l'area messaggi in [`ChatPanelView+RootLayout.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift).
- Aggiunto riordino dedicato [`ChatTurnTimelineSubagentOrdering.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineSubagentOrdering.swift) e collegato all’interleaver in [`ChatTurnTimelineInterleaver.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift) per spostare eventuali subagent trailing prima dell'ultimo testo finale.

## Test
- [`ChatFinalActionsPlacementPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatFinalActionsPlacementPolicyTests.swift)
- [`ChatTimelineInterleavingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingTests.swift)

## Rischi controllati
- Nessun cambio al layout interno del footer finale.
- Nessun cambio al contenuto delle card subagent.
- Nessun cambio alle regole di grouping di tool/file/terminal.
