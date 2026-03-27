# Analisi Colli di Bottiglia Performance — Round 2

**Data**: 2026-03-27
**Scope**: runtime app macOS (SwiftUI), startup/indexing, pipeline snapshots, build/test overhead
**Metodo**:
- audit statico dei path caldi nel codice Swift
- lettura del sample reale `.cursor/debug-7e54b6-sample.txt`
- benchmark selettivi via `xcodebuild test`

## Misure rapide raccolte

- `CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
  - dataset sintetico default: 40 file
  - log runtime: `SemanticIndex.buildIndex` completato in circa `12-13 ms`
  - conclusione: il micro-path BM25 su dataset piccoli non e' il collo di bottiglia principale
- `ValidationPerformanceTests/testSelectorPerformanceOnLargeFileList`
  - media misurata: circa `0.003 s`
  - conclusione: il selettore test mirati non e' prioritario
- sample reale `.cursor/debug-7e54b6-sample.txt`
  - hotspot confermato: `WorkspaceStore.indexActiveWorkspace() -> CodebaseIndex.indexWorkspace(...)`
  - hotspot secondario concreto: `CodebaseIndex.addIndexedFile(_)` con tempo assorbito da `Sequence.contains(where:)`

---

## P1 — Chat snapshot refresh ancora troppo largo sul MainActor

- Categoria: B — Importante
- Bug: ogni tick di streaming riesegue un refresh che legge piu' store e aggiorna molto stato UI nello stesso passaggio
- Sintomo: durante streaming e aggiornamenti task la UI continua a rivalutare snapshot e chrome anche quando il delta visibile e' minimo
- Impatto: frame drop, input lag, maggiore costo CPU sul main thread
- Scope consentito: chat snapshot refresh, binding di refresh, pipeline snapshot per conversazione
- Non-scope: refactor del modello messaggi o del bridge Rust
- Expected result: ogni tick deve aggiornare solo il minimo stato visibile necessario
- Rischi laterali: regressioni di sincronizzazione tra snapshot chat, overlay live e stato pipeline

### Evidenza codice

- [App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift](../../App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift)
  - `streaming.streamContentVersion` chiama `refreshMessagesSnapshot()` a ogni tick
  - anche il cambio di `chatStore.activeTaskConversationIds` richiama lo stesso refresh
- [App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift](../../App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift)
  - il refresh legge `chatStore`, `pipelineIntegrationService`, `swarmProgressStore`, `taskActivityStore`
  - aggiorna `snapshotRootLayoutSwarmSteps`, `snapshotRootLayoutSwarmCards`, `snapshotRootLayoutActivities`, `snapshotPipelineConversationSnapshot`, `snapshotIsLoading`, `snapshotChromeLoading`, `messagesConversationSnapshot`

### File/Righe chiave

- `refresh` per tick stream: `ChatPanelView+PartC_MessageAreaRefreshModifiers.swift:13-29`
- fan-out di letture/scritture nello snapshot: `ChatPanelView+PartC_MessageSnapshotRefresh.swift:9-67`
- ulteriore confronto e replace snapshot: `ChatPanelView+PartC_MessageSnapshotRefresh.swift:69-215`

### Strategia minima consigliata

- separare il refresh testo dal refresh chrome/task activity
- aggiornare `snapshotPipelineConversationSnapshot` solo tramite publisher per-conversation, non dentro ogni tick testo
- introdurre un fingerprint piu' stretto per il solo ultimo messaggio invece di ricontrollare piu' slice di stato a ogni evento

---

## P1 — Sidebar invalida e ricostruisce snapshot globali troppo spesso

- Categoria: B — Importante
- Bug: la sidebar reagisce a `chatStore.objectWillChange` globale e ricostruisce snapshot/render state globali sul `MainActor`
- Sintomo: durante streaming o mutazioni todo/tool trace la lista thread viene filtrata, ordinata e ricalcolata anche se cambia un solo thread
- Impatto: lavoro ripetuto sulla UI, pressione sul main thread, latenza visibile su workspace con molte conversazioni
- Scope consentito: scheduling snapshot sidebar, fingerprinting, render state per-thread
- Non-scope: redesign UI sidebar
- Expected result: aggiornare solo il thread o il bucket effettivamente cambiato
- Rischi laterali: lista thread incoerente se la granularita' viene ridotta male

### Evidenza codice

- [App/SoloCodeApp/Sources/App/Sidebar/SidebarView.swift](../../App/SoloCodeApp/Sources/App/Sidebar/SidebarView.swift)
  - `chatStore.objectWillChange` scatena sempre `scheduleSidebarSnapshotRefresh()`
  - `todoStore.objectWillChange` e `toolTraceStore.objectWillChange` scatena sempre il refresh render state
- [App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift](../../App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift)
  - lo scheduler calcola prima il fingerprint e poi ricostruisce lo snapshot
- [App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadListSnapshot.swift](../../App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadListSnapshot.swift)
  - `snapshotFingerprint(...)` e `build(...)` richiamano entrambi `filteredThreads(...)`
  - `filteredThreads(...)` filtra + ordina l'intero array `chatStore.conversations`
  - `buildRenderStates(...)` scorre tutte le conversazioni visibili e legge piu' store

### File/Righe chiave

- trigger globali: `SidebarView.swift:62-88`
- doppio passaggio fingerprint + build: `SidebarView+Support.swift:46-98`
- filtro/sort duplicato: `SidebarThreadListSnapshot.swift:67-156`
- render states per tutte le righe: `SidebarThreadListSnapshot.swift:162-220`

### Strategia minima consigliata

- passare da invalidazione globale a invalidazione per conversation id
- evitare doppio `filteredThreads(...)`: riusare il risultato tra fingerprint e build
- mantenere una cache dei `SidebarThreadRenderState` per thread invece di rigenerare l'intero dizionario

---

## P1 — Lo startup resta dominato da full scan del workspace prima del lavoro davvero parallelo

- Categoria: B — Importante
- Bug: `indexWorkspace` fa traversal filesystem e costruzione albero completi prima di arrivare alla fase parallelizzata
- Sintomo: allo startup la barra di indexing parte subito ma il costo iniziale resta alto su workspace grandi
- Impatto: launch piu' lento, attivazione workspace ritardata, CPU e I/O iniziali elevati
- Scope consentito: traversal filesystem, build file tree, bootstrap indexing
- Non-scope: cambiare il formato semantico o il comportamento funzionale della ricerca
- Expected result: ridurre lavoro seriale upfront e spostare il piu' possibile su path incrementali/lazy
- Rischi laterali: incoerenza del tree explorer o progress reporting incompleto

### Evidenza codice

- [App/SoloCodeApp/Sources/Services/Project/WorkspaceStore.swift](../../App/SoloCodeApp/Sources/Services/Project/WorkspaceStore.swift)
  - lo startup bootstrap richiama `index.indexWorkspace(...)`
- [Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift](../../Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift)
  - `rebuildWorkspaceFileTrees()` avviene prima della fase `indexFilesInParallel`
- [Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift](../../Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift)
  - `buildFileTree(...)` usa recursion + `contentsOfDirectory` + sort per ogni cartella

### Evidenza sample reale

- `.cursor/debug-7e54b6-sample.txt`
  - `3325` sample nel thread `WorkspaceStore.indexActiveWorkspace()`
  - la catena dominante passa da `CodebaseIndex.indexWorkspace(...)`

### File/Righe chiave

- bootstrap indexing: `WorkspaceStore.swift:104-177`
- full scan iniziale: `CodebaseIndex+WorkspaceIndexing.swift:43-52`
- traversal ricorsiva con sort per directory: `CodebaseIndex+IndexHelpers.swift:10-75`

### Strategia minima consigliata

- separare file tree explorer dal set minimo necessario all'index bootstrap
- usare inventory incrementale o traversal streaming senza materializzare subito tutto l'albero
- evitare sort di ogni directory nella fase di bootstrap se non strettamente richiesto dal contratto utente

---

## P1 — `CodebaseIndex.addIndexedFile` ha un costo O(n²) sui simboli gia' indicizzati

- Categoria: B — Importante
- Bug: per ogni simbolo vengono eseguiti fino a tre `contains(where:)` lineari su array di simboli esistenti
- Sintomo: il costo cresce in modo non lineare con file ricchi di simboli o cache hydrate grandi
- Impatto: CPU extra proprio nel path di indexing gia' identificato dal sample
- Scope consentito: strutture ausiliarie `symbolsByName`, `symbolsByFile`, `symbolsByKind`
- Non-scope: cambiare il formato pubblico dei simboli o del risultato ricerca
- Expected result: inserimento simboli quasi lineare nel numero di simboli nuovi
- Rischi laterali: duplicati se la deduplica cambia comportamento

### Evidenza codice

- [Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift](../../Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift)
  - `addIndexedFile(_)` fa `contains(where:)` su `symbolsByName`, `symbolsByFile`, `symbolsByKind`

### Evidenza sample reale

- `.cursor/debug-7e54b6-sample.txt`
  - `2468` sample in `CodebaseIndex.addIndexedFile(_)`
  - `1807` sample figlio in `Sequence.contains(where:)`

### File/Righe chiave

- `CodebaseIndex+IndexHelpers.swift:115-145`

### Strategia minima consigliata

- mantenere set di id per bucket (`[String: Set<String>]`, `[FileLanguage: Set<String>]` o equivalenti)
- append agli array solo quando l'id non e' gia' presente nel set
- in alternativa, costruire bucket nuovi una sola volta per file invece di fare check per simbolo su array crescenti

---

## P2 — `PipelineIntegrationService.snapshotsByConversation` resta una invalidazione larga

- Categoria: B — Importante ma non bloccante
- Bug: la mappa snapshot e' `@Published`, quindi ogni flush emette `objectWillChange` sull'intero service
- Sintomo: anche con `snapshotDidChange` per-conversation, le view che osservano il service possono essere invalidate piu' del necessario
- Impatto: lavoro SwiftUI addizionale durante streaming/pipeline jobs
- Scope consentito: meccanismo di pubblicazione snapshot
- Non-scope: logica di esecuzione job pipeline
- Expected result: notifiche limitate alla conversazione realmente cambiata
- Rischi laterali: perdita aggiornamenti se il publisher granulare non copre tutti i consumer

### Evidenza codice

- [App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift](../../App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift)
  - `@Published var snapshotsByConversation`
- [App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+Snapshots.swift](../../App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+Snapshots.swift)
  - esiste gia' `snapshotDidChange`, quindi il tipo e' pronto per una migrazione a notifiche piu' strette

### File/Righe chiave

- `PipelineIntegrationService.swift:82-85`
- `PipelineIntegrationService+Snapshots.swift:49-95`

### Strategia minima consigliata

- rendere la mappa interna non `@Published`
- usare solo `snapshotDidChange` o publisher dedicati per conversation id

---

## P2 — Build overhead evitabile: script `Sync tool_descriptions Swift` gira sempre

- Categoria: C — Minore, ma con costo cumulativo alto
- Bug: la phase Xcode e' marcata `alwaysOutOfDate = 1`
- Sintomo: ogni build/test rilancia lo script anche quando gli input non cambiano
- Impatto: build incrementali piu' lente e rumore costante nel ciclo profiling/test
- Scope consentito: build phase Xcode
- Non-scope: contenuto del file generato
- Expected result: eseguire lo script solo quando cambiano gli input dichiarati
- Rischi laterali: descrizioni tool stale se input/output non sono dichiarati correttamente

### Evidenza codice

- [Solo Code.xcodeproj/project.pbxproj](../../Solo%20Code.xcodeproj/project.pbxproj)
  - phase `Sync tool_descriptions Swift`
  - `alwaysOutOfDate = 1`

### Evidenza test locale

- sia il benchmark smoke sia il test performance hanno riportato:
  - `Run script build phase 'Sync tool_descriptions Swift' will be run during every build`

### File/Righe chiave

- `project.pbxproj:733-755`

### Strategia minima consigliata

- riabilitare dependency analysis
- mantenere input/output dichiarati come gia' presenti nella phase

---

## Non-prioritari confermati

- `TargetedTestsSelector.select(...)` non appare hotspot: benchmark locale circa `3 ms` medi su 1000 file
- `SemanticIndex.buildIndex` su micro dataset sintetico e' veloce; il problema reale e' il contorno di startup/index bootstrap, non il benchmark minimo

## Priorita' consigliata di intervento

1. ridurre `refreshMessagesSnapshot()` e separare refresh testo da chrome/task
2. togliere invalidazione globale della sidebar e cacheare meglio fingerprint/render state
3. ottimizzare `addIndexedFile(_)` prima di ulteriori refactor dell'indexer
4. ridurre il full scan iniziale del workspace o renderlo piu' lazy
5. restringere le notifiche di `PipelineIntegrationService`
6. sistemare la build phase sempre out-of-date
