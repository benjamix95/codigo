# 2026-03-09 — Deferral dei publish SwiftUI fuori dal render pass

## Obiettivo
Eliminare i warning `Publishing changes from within view updates is not allowed` senza cambiare la logica funzionale dei pannelli live.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Buffering.swift`
  - il flush immediato di `addActivity()` ora viene schedulato sul prossimo tick del main run loop
  - il flush differito continua a usare il debounce esistente, ma pubblica fuori dal render pass
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - il sink che applica `chatThreads` / `activeChatThreadId` usa ora un deferral esplicito su `DispatchQueue.main.async`
- aggiornato `App/SoloCodeApp/Sources/Runtime/WorkspaceStore.swift`
  - gli update di `indexProgress` e il reset finale a `nil` vengono pubblicati fuori dal frame corrente
- aggiornato `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - le mutazioni di `chatMessages` e `taskActivityStore` da eventi raw review vengono differite al tick successivo
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
  - i test che assumevano flush sincrono chiamano ora `flushPending()` in modo esplicito

## Validazione eseguita
- `xcodebuild build -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests -only-testing:CoderEngineTests/MCPSessionManagerTests`

## Impatto atteso
- riduzione dei warning SwiftUI in task activity, review panel e workspace indexing
- eliminazione della publish reentrante durante il render pass
- mantenimento del comportamento visibile, con un ritardo massimo di un tick di main loop per gli aggiornamenti live
