# 2026-03-08 - Review panel chat focus bug/security e rendering markdown

- Documentato il problema in [P1-2026-03-08-review-panel-chat-focus-and-markdown-formatting.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-08-review-panel-chat-focus-and-markdown-formatting.md).
- Rafforzato [ReviewPanelCoordinator+Prompts.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Coordinator/ReviewPanelCoordinator+Prompts.swift) per imporre alla chat review focus esplicito su bug hunting, security review, uso degli strumenti disponibili e output markdown strutturato.
- Aggiornato [ReviewPanelChatBubble.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatBubble.swift) per passare il `ProjectContext` al bubble review.
- Aggiornato [ReviewPanelChatBubble+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatBubble+Helpers.swift) per sostituire il fallback `Text(...)` con `MarkdownContentView`, mantenendo il rendering strutturato esistente per summary e review run.
- Aggiornato [ReviewPanelChatTab.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatTab.swift) per fornire il contesto workspace al renderer markdown e chiarire l'empty state della review chat.
- Estesa la copertura in [ReviewPanelChatStructuredContentTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPanelChatStructuredContentTests.swift) con una verifica sul nuovo contratto del prompt review chat.
