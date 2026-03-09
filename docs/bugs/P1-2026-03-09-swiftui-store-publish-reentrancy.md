# P1 — Store SwiftUI pubblicavano cambiamenti durante il render pass

## Bug Fix Record
- Categoria: B
- Bug: alcuni store SwiftUI (`TaskActivityStore`, `CodeReviewPanelStore`, `WorkspaceStore`) mutavano proprietà `@Published` nello stesso frame in cui SwiftUI stava ancora aggiornando la view hierarchy.
- Sintomo: warning runtime ripetuti `Publishing changes from within view updates is not allowed, this will cause undefined behavior.` con stack centrati su buffering task activity, sync chat threads, progress workspace e action output review.
- Impatto: comportamento UI non deterministico, warning storm e rischio di loop/render incoerenti nei pannelli live.
- Gravità: alta
- Steps to reproduce:
  1. Aprire Solo Code con pannelli Task Activity / Code Review attivi.
  2. Generare eventi live di review, swarm o indicizzazione workspace.
  3. Osservare warning SwiftUI sui file `TaskActivityStore+Buffering.swift`, `TaskActivityStore+Swarm.swift`, `CodeReviewPanelStore+ModesAndChatThreads.swift`, `WorkspaceStore.swift`, `CodeReviewPanelStore+ActionOutput.swift`.
- Risultato attuale: le mutazioni osservabili avvengono nel render pass corrente.
- Risultato atteso: le mutazioni che arrivano da callback live devono essere deferrate al tick successivo del main run loop.
- Causa probabile: `Task.yield()` non garantiva uscita dal frame di update SwiftUI; serviva un deferral esplicito con `DispatchQueue.main.async` nei punti di publish reentrante.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Buffering.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - `App/SoloCodeApp/Sources/Runtime/WorkspaceStore.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - redesign dei flussi chat/review
  - refactor dei model store
  - modifica dei reducer swarm o del formato eventi
- Moduli confinanti da verificare:
  - `TaskActivityStore+Swarm`
  - `CodeReviewPanelStore+ModesAndChatThreads`
  - `WorkspaceStore`
  - `CodeReviewPanelStore+ActionOutput`
- Test da aggiungere o aggiornare:
  - aggiornare i test swarm che assumevano flush sincrono dopo `addActivity()`
  - rieseguire le suite mirate su task activity, session scoping review e MCP session manager
- Strategia di fix minimo:
  - deferrire il flush immediato di `TaskActivityStore` al prossimo main-loop tick
  - deferrire sync chat conversation, progress workspace e action output review con `DispatchQueue.main.async`
  - mantenere `flushPending()` come via sincrona esplicita per i test
- Verifica post-fix:
  - `xcodebuild build -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests -only-testing:CoderEngineTests/MCPSessionManagerTests`
- Commit previsto: `fix(ui): defer store publishes outside render pass`

## Evidenza raccolta
- Warning riportati su:
  - `TaskActivityStore+Buffering.swift:12,18,39,123,126`
  - `TaskActivityStore+Swarm.swift:25`
  - `CodeReviewPanelStore+ModesAndChatThreads.swift:88`
  - `WorkspaceStore.swift:153`
  - `CodeReviewPanelStore+ActionOutput.swift:216,218,242`
- Pattern comune:
  - callback live o sink Combine già sul main actor
  - mutazione `@Published` nello stesso ciclo di aggiornamento della UI
  - warning SwiftUI a cascata senza necessità di cambiare la logica di business
