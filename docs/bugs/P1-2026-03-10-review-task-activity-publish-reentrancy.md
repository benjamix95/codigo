# P1 — Publish reentranti tra `TaskActivityStore` e `CodeReviewPanelStore` durante update SwiftUI

## Bug Fix Record
- Categoria: A
- Bug: alcuni bridge review live reiniettavano `CodeReviewSessionSnapshot` nel `TaskActivityStore` nello stesso frame in cui SwiftUI stava ancora aggiornando il pannello review, mentre `CodeReviewPanelStore` rilanciava `objectWillChange` in modo sincrono.
- Sintomo: warning runtime `Publishing changes from within view updates is not allowed`, spam `AttributeGraph`, pannello review instabile e possibili freeze con state storm.
- Impatto: comportamento UI non deterministico su Code Review / Task Activity, invalidazioni a cascata e rischio di blocco percepito.
- Gravità: alta
- Steps to reproduce:
  1. avviare una review dal pannello o da runtime provider chat
  2. ricevere snapshot review live con `onStateChange`
  3. osservare warning su `TaskActivityStore+CodeReview.swift`, `TaskActivityStore+Buffering.swift`, `TaskActivityStore+Swarm.swift`, `CodeReviewPanelStore+Launch.swift`, `CodeReviewPanelStore.swift`
- Risultato attuale:
  - i bridge review chiamavano `ingestCodeReviewSnapshot(...)` inline sul main actor
  - il pannello rilanciava `objectWillChange.send()` immediatamente quando il `TaskActivityStore` pubblicava
- Risultato atteso:
  - gli snapshot review live devono essere reiniettati al tick successivo del main run loop
  - il relay `TaskActivityStore -> CodeReviewPanelStore` deve essere differito, non sincrono
- Causa probabile: la regressione ha riaperto un path già fragile in cui callback live (`onStateChange`, patch workflow, chat findings, runtime provider) mutano store osservati dentro il render pass SwiftUI.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift`
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Buffering.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_TaskActivity.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_CodeReviewMutations.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewDeferredCommands.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewPatchCommands.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommandMutations.swift`
  - `App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+VerifiedFindingsReview.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - refactor architetturale completo degli store review/task
  - modifica dei reducer swarm
  - cambiamenti al modello persistence
- Moduli confinanti da verificare:
  - `TaskActivityStore+Buffering`
  - `TaskActivityStore+Swarm`
  - `CodeReviewPanelStore+Launch`
  - `CodeReviewPanelStore+PatchWorkflow+Execution`
  - `ChatPanelView+PartN_RuntimeProvider`
- Test da aggiungere o aggiornare:
  - regressione sullo scheduling di `scheduleCodeReviewSnapshotIngest(...)`
  - suite panel/task deferral e swarm cards
- Strategia di fix minimo:
  - introdurre helper di defer basati su `Task.yield()` nel `TaskActivityStore`
  - usare `scheduleCodeReviewSnapshotIngest(...)` in tutti i bridge review live che reiniettano snapshot nello store UI
  - differire anche il relay `taskActivityStore.objectWillChange` e il bind `panelSessionId` del panel review
  - spostare il path `appendOrMergeBatchEvent(...)` del flush chat al tick successivo per evitare publish immediati durante update SwiftUI
- Verifica post-fix:
  - `SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
  - `SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests`
  - `SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- Commit previsto: `fix(review): defer task activity publishes outside view updates`

## Evidenza
Warning segnalati su:

```text
TaskActivityStore+Swarm.swift:25
TaskActivityStore+Buffering.swift:32, 44, 129, 132
TaskActivityStore+CodeReview.swift:46-56
CodeReviewPanelStore+Launch.swift:49, 52
CodeReviewPanelStore.swift:161
```
