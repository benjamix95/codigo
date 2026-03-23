# P1 — Follow-up: publish reentranti residui in TaskActivityStore e review mutation hooks

## Bug Fix Record
- Categoria: B
- Bug: dopo il primo hardening SwiftUI restavano due path reentranti:
  - snapshot finale delle card swarm nel `ChatPanelView`
  - ingest dei `CodeReviewSessionSnapshot` dal mutation flow runtime
- Sintomo: warning runtime `Publishing changes from within view updates is not allowed` su:
  - `TaskActivityStore+Swarm.swift:25`
  - `TaskActivityStore+Buffering.swift:32,44,129,132`
  - `TaskActivityStore+CodeReview.swift:46-49`
  - `SoloCodeApp+CodeReviewCommandMutations.swift:81`
- Impatto: comportamento UI non deterministico durante chiusura task e sincronizzazione live delle review.
- Gravità: alta
- Steps to reproduce:
  1. Eseguire un task con subagent/swarm cards attive.
  2. Chiudere il task mentre esistono ancora eventi buffered nello store.
  3. Oppure applicare una mutation review live che persiste e reinietta uno snapshot nello store.
  4. Osservare i warning SwiftUI sui file sopra.
- Risultato attuale: alcuni percorsi facevano ancora flush/persist+ingest sincroni nel frame di update della UI.
- Risultato atteso: lo snapshot chat deve essere derivato senza pubblicare nello store; gli snapshot review live devono essere reiniettati nel tick successivo.
- Causa probabile:
  - `snapshotSubagentCardsAndEndTask()` chiamava `flushPending()` e `finalizeRunningSwarmCards()` in un callback UI.
  - `persistLiveReviewState()` e `persistReviewSnapshotMutation()` richiamavano `taskActivityStore.ingestCodeReviewSnapshot(...)` inline.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartE_TaskLifecycle.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommandMutations.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/SoloCodeApp+CodeReviewDeferredCommands.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - refactor strutturale di `TaskActivityStore`
  - redesign del review pipeline
  - modifica del reducer swarm
- Moduli confinanti da verificare:
  - `TaskActivityStore+Swarm`
  - `TaskActivityStore+CodeReview`
  - `ChatPanelView+PartE_TaskLifecycle`
  - `SoloCodeApp+CodeReviewCommandMutations`
- Test da aggiungere o aggiornare:
  - copertura per `swarmCardStatesIncludingPending()`
  - riesecuzione delle suite swarm, scoped activities e command loop review
- Strategia di fix minimo:
  - introdurre uno snapshot swarm derivato da `activities + pendingActivities` senza publish
  - finalizzare le card per il salvataggio chat solo in memoria locale
  - differire con `DispatchQueue.main.async` l’ingest dei review snapshot runtime
- Verifica post-fix:
  - `xcodebuild build -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests -only-testing:CoderEngineTests/MCPSessionManagerTests`
- Commit previsto: `fix(ui): avoid reentrant swarm and review snapshot publishes`

## Evidenza raccolta
- Il path `snapshotSubagentCardsAndEndTask()` non aveva bisogno di mutare lo store per costruire la snapshot finale: bastava ridurre `activities + pendingActivities`.
- Il mutation flow review persisteva e reiniettava snapshot nello stesso frame; il contenuto era corretto, il timing di publish no.
