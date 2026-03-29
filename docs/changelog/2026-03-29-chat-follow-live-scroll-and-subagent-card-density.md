# Changelog — 2026-03-29

## Chat
- Il follow-live della chat principale ora si sospende quando l'utente scorre manualmente lontano dal fondo e si riattiva quando torna vicino al bottom anchor.
- Lo scroll programmatico della chat marca i propri aggiornamenti viewport per non auto-disattivarsi durante i `scrollTo` interni.

## Subagent
- Le card subagent live e snapshot sono più compatte in altezza: padding verticali ridotti, task prompt più corto in stato collassato, preview compatta ridotta e area espansa leggermente più contenuta.
- Nessun cambio di struttura o layout generale delle card.

## File principali
- [`ChatAutoScrollFollowPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatAutoScrollFollowPolicy.swift)
- [`ChatMessagesScrollViewportObserver.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatMessagesScrollViewportObserver.swift)
- [`ChatPanelView+PartC_MessageViewportFollow.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageViewportFollow.swift)
- [`SubagentChatCardCompactPresentation.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Swarm/Views/SubagentChatCardCompactPresentation.swift)
