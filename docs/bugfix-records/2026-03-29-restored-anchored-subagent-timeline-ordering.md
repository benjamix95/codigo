# Bugfix Record — 2026-03-29

## Scope
- Ripristinare l’ordering cronologico corretto dei subagent nella timeline del turno.
- Mantenere il footer finale `Task completed` in basso, senza reintrodurlo nella chrome alta.

## Modifiche
- Rimosso il post-processing che forzava i segmenti subagent prima dell’ultimo testo finale da [`ChatTurnTimelineInterleaver.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift).
- Eliminato il helper introdotto per quel riordino, perché alterava la cronologia effettiva del turno.
- Mantenuto il footer finale sotto l’area messaggi tramite [`ChatFinalActionsPlacementPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatFinalActionsPlacementPolicy.swift) e [`ChatPanelView+RootLayout.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift).
- Estese le regressioni in [`ChatTimelineInterleavingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingTests.swift) per coprire:
  - snapshot trailing senza anchor che restano in coda cronologica;
  - snapshot con `swarm_id` ancorate alla sequence delle operazioni;
  - preservazione dei blocchi testuali multipli con subagent e tool interleavati.

## Test
- [`ChatTimelineInterleavingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingTests.swift)
- [`ChatFinalActionsPlacementPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatFinalActionsPlacementPolicyTests.swift)
- [`ChatPanelFinalActionsVisibilityTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPanelFinalActionsVisibilityTests.swift)

## Rischi controllati
- Nessuna alterazione del layout del footer finale.
- Nessuna alterazione del rendering interno delle card subagent.
- Nessun rollback delle fix pregresse su synthetic timeline interleaving.
