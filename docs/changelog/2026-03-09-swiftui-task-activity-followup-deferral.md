# 2026-03-09 — Follow-up: snapshot swarm e review ingest fuori dal render pass

## Obiettivo
Chiudere i warning SwiftUI residui rimasti dopo il primo fix di deferral dei publish.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
  - aggiunge `swarmCardStatesIncludingPending(...)` per derivare card live da `activities + pendingActivities` senza mutare lo store
- aggiornato `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartE_TaskLifecycle.swift`
  - la snapshot finale dei subagent non usa più `flushPending()` o `finalizeRunningSwarmCards()`
  - le card running vengono finalizzate solo nella copia locale salvata nel messaggio chat
- aggiornato `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommandMutations.swift`
  - `persistLiveReviewState(...)` e `persistReviewSnapshotMutation(...)` differiscono l’ingest nello store al tick successivo
- aggiornato `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/SoloCodeApp+CodeReviewDeferredCommands.swift`
  - anche il path `onStateChange` del command review usa un ingest differito
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
  - aggiunge copertura per lo snapshot swarm che include attività buffered senza flush

## Validazione eseguita
- `xcodebuild build -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests -only-testing:CoderEngineTests/MCPSessionManagerTests`

## Impatto atteso
- meno warning SwiftUI durante chiusura task con card swarm attive
- meno warning durante apply/configure/start dei command review live
- nessun cambio funzionale nel contenuto delle snapshot o delle card visibili
