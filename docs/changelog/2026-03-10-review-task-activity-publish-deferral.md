# 2026-03-10 — Deferral publish review/task activity fuori dal render pass

## Obiettivo
Spezzare la cascata di publish SwiftUI tra `TaskActivityStore` e `CodeReviewPanelStore` durante gli update live della review.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift`
  - aggiunto `scheduleCodeReviewSnapshotIngest(...)` che reinietta lo snapshot review al tick successivo del main queue
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - il relay `taskActivityStore.objectWillChange -> objectWillChange.send()` è ora differito con `DispatchQueue.main.async`
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - gli `onStateChange` del session state non mutano più inline `taskActivityStore` e `panelSessionId`
  - il dismiss live e il targeted fix bootstrap usano ingest differito
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift`
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift`
- aggiornato `App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartN_RuntimeProvider.swift`
  - tutti questi bridge usano ora `scheduleCodeReviewSnapshotIngest(...)` invece di `ingestCodeReviewSnapshot(...)` inline
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
  - aggiunta regressione che verifica il deferral dello snapshot review al tick successivo
- documentato il bug in `docs/bugs/P1-2026-03-10-review-task-activity-publish-reentrancy.md`

## Validazione eseguita
```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests \
  -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests \
  -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests \
  -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests
```

## Note
- Fix confinato ai bridge review/task activity; nessun cambiamento alla persistence.
- I warning MCP `pid 400`, `node`, `npx` e i problemi di scrittura file `sessions/bughunter` restano separati da questo bug.
