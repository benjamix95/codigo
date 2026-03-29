# Bugfix Record — 2026-03-29

## Scope
- Sospendere il follow-live della chat quando l'utente si allontana manualmente dal fondo.
- Ridurre l'altezza compatta delle card subagent senza cambiare il layout.

## Modifiche
- Aggiunta policy dedicata [`ChatAutoScrollFollowPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatAutoScrollFollowPolicy.swift) per decidere quando mantenere o sganciare `isFollowingLive`.
- Aggiunto observer [`ChatMessagesScrollViewportObserver.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatMessagesScrollViewportObserver.swift) per leggere la posizione reale dello `NSScrollView` della chat senza cambiare il layout.
- Aggiunto handler [`ChatPanelView+PartC_MessageViewportFollow.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageViewportFollow.swift) che spegne il follow-live fuori fondo e lo riattiva quando il viewport torna vicino al bottom anchor.
- Lo scheduler [`ChatPanelView+PartE_TaskLifecycle+Run.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle+Run.swift) marca ora gli scroll programmatici per non confondere i callback del viewport con input manuale.
- Compattate le metriche delle card subagent tramite [`SubagentChatCardCompactPresentation.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatCardCompactPresentation.swift), applicate a [`SubagentChatCard+Snapshot.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatCard+Snapshot.swift), [`SubagentChatCard+SnapshotCard.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatCard+SnapshotCard.swift) e [`SubagentChatView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatView.swift).

## Test
- [`ChatAutoScrollFollowPolicyTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatAutoScrollFollowPolicyTests.swift)
- [`SubagentChatCardCompactPresentationTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SubagentChatCardCompactPresentationTests.swift)

## Rischi controllati
- Nessun cambio di layout della chat.
- Nessun cambio alla timeline tool o alla sidebar.
- Nessun cambio ai contenuti mostrati nelle card subagent, solo densità e limiti preview.
