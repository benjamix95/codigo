# 2026-03-09 — Review panel chat session pinning

## Cosa cambia
- la chat del review panel ora pinna subito la sessione review corrente in `panelSessionId`
- le richieste chat che sembrano review generiche vengono reinterpretate come analisi della sessione attiva, non come autorizzazione implicita a chiamare `review_start`
- il prompt della chat review esplicita:
  - riusa `session_id` corrente
  - non aprire nuove review session salvo richiesta esplicita di nuova sessione/run

## File principali
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatSession.swift`
- `Tests/SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests.swift`

## Test
- `SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests`
- `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
- `SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Note
- fix confinato al routing/prompt del panel chat
- nessuna modifica ai workflow patch o al core `VerifiedFindings`
