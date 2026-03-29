# Changelog — 2026-03-29

## Chat
- Ripristinato l’ordering cronologico dei subagent nella timeline del turno: le card restano ancorate alle operazioni quando esiste un `swarm_id`/trace anchor; senza anchor restano in coda cronologica.
- Il footer `Task completed` resta sotto la sezione messaggi e non torna nella chrome alta.
- Aumentata la copertura di regressione sulla timeline per evitare il ritorno ai blocchi monolitici.

## File principali
- [`ChatTurnTimelineInterleaver.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift)
- [`ChatPanelView+RootLayout.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift)
- [`ChatTimelineInterleavingTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineInterleavingTests.swift)
