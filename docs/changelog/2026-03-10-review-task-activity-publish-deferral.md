# 2026-03-10 — Hardening publish SwiftUI tra review panel e task activity

## Obiettivo
Eliminare i warning `Publishing changes from within view updates is not allowed` nei bridge tra `CodeReviewPanelStore`, `TaskActivityStore` e flush attività chat.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift`
  - aggiunti helper di defer sul main actor basati su `Task.yield()`
  - introdotti `scheduleCodeReviewSnapshotIngest(...)`, `scheduleAppendOrMergeBatchEvent(...)`, `scheduleAddInstantGrep(...)`, `scheduleAddEnvelope(...)`
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Buffering.swift`
  - il flush buffered non rientra più nello stesso update pass SwiftUI
  - `activeOperationsCount` pubblica solo quando il conteggio cambia davvero
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - il relay `taskActivityStore.objectWillChange -> objectWillChange.send()` è ora differito con `Task.yield()`
  - aggiunto helper per bind differito di `panelSessionId`
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift`
  - `handleIncomingChatConversation(...)` aspetta il tick successivo prima di applicare il mirror della sessione chat
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - gli `onStateChange` live non chiamano più `ingestCodeReviewSnapshot(...)` inline
  - `panelSessionId` viene schedulato invece di essere pubblicato nello stesso callback
- aggiornato `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_TaskActivity.swift`
  - il path `appendOrMergeBatchEvent(...)` del flush chat viene differito
  - anche gli instant grep vengono reiniettati fuori dal render pass
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - l’ingest degli envelope review usa scheduling differito
- aggiornati i bridge review live che reiniettano snapshot:
  - `App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+VerifiedFindingsReview.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_CodeReviewMutations.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewDeferredCommands.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewPatchCommands.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommandMutations.swift`
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
  - aggiunta regressione sul defer del path `scheduleAppendOrMergeBatchEvent(...)`
- mantenuta la regressione esistente su `scheduleCodeReviewSnapshotIngest(...)` in `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
- aggiornata la scheda bug `docs/bugs/P1-2026-03-10-review-task-activity-publish-reentrancy.md`

## Validazione eseguita
```bash
xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests \
  -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests \
  -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests
```

## Esito
- 28 test eseguiti, 0 failure
- scan sicurezza scoped: nessun insecure pattern rilevato

## Note
- Fix confinato ai path di publish/reinject, senza refactor dei reducer o della persistence.
- In questa sessione non era disponibile `xcodebuildmcp`; validazione eseguita con `xcodebuild` locale.
