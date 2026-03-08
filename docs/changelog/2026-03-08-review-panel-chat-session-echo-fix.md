# 2026-03-08 - Fix echo sincrono chat session nel review panel

- Documentato il bug in [P1-2026-03-08-review-panel-chat-session-echo-publish-cycle.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-08-review-panel-chat-session-echo-publish-cycle.md).
- Aggiornato [CodeReviewPanelStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift) per cancellare apply pendenti del mirror chat e differire l’`applyChatConversationState` del `sink` al tick successivo del main actor.
- Aggiunto [CodeReviewPanelChatStateDeferralTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift) con regressione che verifica che `chatThreads` non venga riscritto sincronicamente nello stesso turno di `appendChatMessage`.
