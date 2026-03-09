# 2026-03-09 — Review panel chat session echo freeze regression

## Obiettivo
Bloccare la regressione che riportava il pannello `Code Review` in un loop SwiftUI di publish reentranti, con warning `Publishing changes from within view updates`, cicli `AttributeGraph` e freeze dell’app.

## Modifiche
- ripristinato nel `CodeReviewPanelStore` il mirror della conversazione review differito con `Task.yield()` e cancellazione del task pendente
- eliminato il mirror `DispatchQueue.main.async` nel file `CodeReviewPanelStore+ModesAndChatThreads.swift`
- aggiunte guardie di uguaglianza per evitare nuove emissioni `@Published` quando lo snapshot chat è identico
- aggiunto test di regressione che verifica che `applyChatConversationState` non pubblichi nulla su stato invariato

## File toccati
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift`
- `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
- `docs/bugs/P1-2026-03-09-review-panel-chat-session-echo-freeze-regression.md`

## Validazione
Eseguita con `xcodebuild` su macOS:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests \
  -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests \
  -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests
```

Esito:
- 13 test eseguiti
- 0 failure

## Note
- L’evidenza runtime raccolta durante il fix mostra:
  - main thread saturata in `SwiftUICore` / `AttributeGraph`
  - warning `Publishing changes from within view updates is not allowed`
  - errori MCP `node` / `npx` mancanti che restano separati dal freeze principale
