# Analisi Colli di Bottiglia — Performance & Concurrency

**Data**: 2026-03-26 (aggiornamento implementazione / audit caller: 2026-03-26)
**Scope**: App (SwiftUI + Pipeline) + Engine (SemanticIndex + EventBus + HybridSearch)

---

## Aggiornamento codice & strumentazione

- **Hybrid search (path caldo)**: `SemanticIndex.search` usa solo `searchBackend.asyncSearch` ([SemanticIndex+Search.swift](../../Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Search.swift)). Nessun caller di produzione invoca il `search()` sincrono dell’hybrid backend; il rischio semaforo resta sul **path legacy** `mergeWithVectorSync` se in futuro qualcuno chiamasse `HybridSearchEngineBackend.search` senza passare da `SemanticIndex`.
- **BM25 / eviction**: mitigati in codice — vedi BOTTLENECK-03 e BOTTLENECK-04.
- **Bridge pipeline + UI**: debounce 16ms su eventi stream-only verso Rust; `cachedStoreSnapshot` già presente. Segnaposto OS (`os_signpost`) per audit in Instruments:
  - `EventBusPublish` (DEBUG) — [EventBus.swift](../../Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift)
  - `RustApplyUIIntent` — [RustMainChatAdapterSignpost.swift](../../App/SoloCodeApp/Sources/App/Utilities/RustMainChatAdapterSignpost.swift)
  - `FlushPipelineSnapshots` — [PipelineSnapshotFlushSignpost.swift](../../App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineSnapshotFlushSignpost.swift)
  - `ConsumePipelineEvents` (esistente) — [PipelineIntegrationConsumeEventsSignpost.swift](../../App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationConsumeEventsSignpost.swift)
- **rootLayout**: strip swarm aggiornata da snapshot in `@State` ([ChatPanelView+PartC_MessageScrollState.swift](../../App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageScrollState.swift), [ChatPanelRootSwarmProgressSlot.swift](../../App/SoloCodeApp/Sources/ChatView/Root/ChatPanelRootSwarmProgressSlot.swift)).

---

## BOTTLENECK-01 — HybridSearchEngineBackend: DispatchSemaphore nel path sincrono legacy
**Severità**: **Ridotto a P2 per il path predefinito** — P0 solo se si usa `search()` sincrono sull’hybrid senza `SemanticIndex`.
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift` (`mergeWithVectorSync`, e `asyncSearch` senza semaforo)
**Problema (residuo)**: `mergeWithVectorSync()` usa ancora `DispatchSemaphore` per il protocol `search()` sincrono. Il path **usato da `SemanticIndex`** è `asyncSearch` + `mergeWithVectorAsync`, senza semaforo.
**Audit caller**: ricerca nel modulo App/Engine: nessun uso di `searchBackend.search(`; solo `asyncSearch` da [SemanticIndex+Search.swift](../../Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Search.swift). I test chiamano `SemanticIndex.search` (async) che a sua volta usa `asyncSearch`.
**Fix suggerito (residuo)**:
1. Deprecare o rimuovere il path sincrono hybrid se non servono caller legacy
2. O documentare che il backend hybrid va sempre usato via `asyncSearch` / `SemanticIndex`

---

## BOTTLENECK-02 — SemanticIndex: persist() full-rewrite di tutto l'indice su disco
**Severità**: P1 — Importante
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift:39-76`
**Problema**: Quando ci sono dirty files, `persist()` serializza **tutti** i chunk (fino a 50.000) in JSONL, li ordina, li joina in una singola stringa e la scrive atomicamente su disco. Questo è O(n) sulla dimensione totale dell'indice, non O(dirty_files).
**Impatto**: Con 50K chunk, ogni persist richiede centinaia di MB di allocazione stringa temporanea, sort O(n log n), e I/O disco pesante. Il debounce a 2s mitiga la frequenza, ma ogni singolo persist resta costoso.
**Fix suggerito**:
1. Persist incrementale: scrivere solo i chunk dirty in un file di append log
2. Compaction periodica: riscrivere il file intero solo quando l'append log supera una soglia
3. Usare formato binario (MessagePack/FlatBuffers) invece di JSONL per ridurre allocazioni stringa

---

## BOTTLENECK-03 — SemanticIndex: recalcAvgDocLength() O(n) su ogni singolo file update
**Stato**: **Mitigato in codice** (2026-03).
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+IndexManagement.swift`
**Implementazione**: `totalTokenCount` incrementale; `recalcAvgDocLength()` O(1); `rebuildTotalTokenCount()` O(n) solo dopo `loadFromDisk`.

---

## BOTTLENECK-04 — SemanticIndex: evictIfNeeded() sort O(n log n) su ogni addChunks
**Stato**: **Migliorato in codice**: scan lineare + selezione bounded dei chunk più vecchi (heap) invece del sort completo su tutti i chunk.
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+ChunkBudget.swift`
**Nota**: eviction O(1) “pura” LRU resta un possibile miglioramento futuro se il profilo CPU lo richiede.

---

## BOTTLENECK-05 — ChatPanelView: ~20 @EnvironmentObject + ~35 @State causano re-render cascade
**Severità**: P1 — Importante  
**File**: `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift:7-37` (EnvironmentObjects), `:42-93` (State)
**Problema**: `ChatPanelView` inietta ~20 `@EnvironmentObject` e ~35 `@State`. Ogni `objectWillChange` di qualsiasi EnvironmentObject triggera il re-evaluate dell'intero `body`. Il `rootLayout` accede direttamente a `chatStore`, `taskActivityStore`, `swarmProgressStore`, `pipelineIntegrationService` nel body path, registrando dipendenze SwiftUI su tutti.
**Impatto**: Re-render cascade durante streaming (ogni delta di testo → chatStore.objectWillChange → re-evaluate dell'intero albero view). Il commento nel codice (`~24 idle re-renders at startup`) conferma il problema noto.
**Fix suggerito**:
1. Estrarre sotto-view con scope ridotto (principio di minima dipendenza)
2. Usare `EquatableView` per le sotto-view pesanti
3. Spostare le letture di store dal body a computed/onChange dedicati
4. Considerare `@Observable` (macro) per dependency tracking granulare

---

## BOTTLENECK-06 — RustMainChatStoreAdapter: serializzazione/deserializzazione completa su ogni azione
**Severità**: P1 — Importante (parzialmente mitigato)
**File**: `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`, `PipelineIntegrationService+ChatPipeline.swift`
**Mitigazioni in codice**:
- `cachedStoreSnapshot` sul runtime pipeline (meno snapshot Swift su ogni batch FFI)
- Debounce **16ms** per eventi singoli `.textDelta` / `.textReplace` / `.reasoningDelta` prima del commit bridge (coalescing con flush su eventi non-stream o teardown)
- Signpost `RustApplyUIIntent` (DEBUG) per misurare il round-trip in Instruments
**Problema residuo**: snapshot completo lato modello se la cache è invalida; delta-based bridge resta il passo successivo ad alto impatto.
**Fix suggerito (residuo)**:
1. Delta-based bridge: passare solo la conversazione/messaggio modificato
2. Dirty flag per conversazione: serializzare solo le conversazioni modificate

---

## BOTTLENECK-07 — PipelineIntegrationService.snapshotsByConversation è @Published
**Severità**: P2 — Moderato
**File**: `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift:81`
**Problema**: `snapshotsByConversation` è `@Published`, quindi ogni `flushSnapshotNow` e `scheduleSnapshotFlush` (che aggiorna il dizionario) triggera `objectWillChange`. Il coalescing via `DispatchQueue.main.async` mitiga, ma ogni flush comunque causa una notifica SwiftUI.
**Impatto**: Re-render addizionali delle view che osservano PipelineIntegrationService, sovrapposti ai re-render da ChatStore.
**Fix suggerito**: Usare un pattern di notifica selettiva (e.g. `CurrentValueSubject` per singola conversazione) o rendere la proprietà non-Published e notificare manualmente solo quando cambia lo stato visibile.

---

## BOTTLENECK-08 — EventBus: idempotency key pruning e delivery sequenziale
**Severità**: P2 — Moderato
**File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift`
**Nota**: routing subscription usa già indice `subscriptionIdsByType` + wildcard (non più scan lineare di tutte le subscription per tipo evento).
**Problema**: 
1. `pruneIdempotencyKeysInternal` viene chiamato su **ogni publish**, anche se il pruning è throttled internamente. La check del timestamp ha comunque overhead.
2. La delivery a subscriber è sequenziale (for loop su matchingSubscriptions con await). Se un subscriber è lento, blocca la delivery a tutti gli altri.
3. `seenIdempotencyKeys` può crescere fino a 10K entries con lookup O(1) ma il pruning è O(n).
**Strumentazione**: signpost `EventBusPublish` (DEBUG) per profilare la durata di `publish`.
**Impatto**: Sotto alto throughput di eventi (streaming testo), la delivery sequenziale e il pruning ripetuto aggiungono latenza.
**Fix suggerito**:
1. Fan-out parallelo: usare `TaskGroup` per delivery concorrente ai subscriber
2. Pruning lazy: eseguire solo quando il dizionario supera una soglia, non su ogni publish

---

## BOTTLENECK-09 — conversations.firstIndex usato ~24 volte nel codebase
**Severità**: P2 — Moderato
**File**: Multipli (`ChatStore+RustBridge.swift`:6 occorrenze, `ChatStoreConversations.swift`:3, ecc.)
**Problema**: `conversations.firstIndex(where:)` è O(n) sull'array delle conversazioni. Usato ripetutamente per trovare una conversazione per ID durante lo streaming, dove lo stesso ID viene cercato centinaia di volte.
**Impatto**: Con molte conversazioni, ogni lookup lineare aggiunge latenza cumulativa.
**Fix suggerito**: Mantenere un `Dictionary<UUID, Int>` come indice secondario per lookup O(1), invalidato quando l'array cambia.

---

## BOTTLENECK-10 — AgentWorkerEventBridge: SequenceGenerator actor overhead per-event
**Severità**: P2 — Moderato
**File**: `Engine/CoderEngine/Sources/AgentPipeline/Bridge/AgentWorkerEventBridge.swift:14-21`
**Problema**: `SequenceGenerator` è un actor con un singolo counter. Ogni evento (textDelta, textReplace, raw) richiede un `await sequencer.next()`, che implica un actor hop. Durante streaming ad alta frequenza, questo serializza tutti gli eventi su un singolo actor.
**Impatto**: Bottleneck di serializzazione su streaming ad alta frequenza.
**Fix suggerito**: Usare `OSAtomicIncrement64` o `AtomicUInt64` (swift-atomics) per incremento lock-free senza actor hop.

---

## BOTTLENECK-11 — NSLock sparsi nel codebase Engine senza profiling
**Severità**: P2 — Moderato  
**File**: Multipli (RustSearchFFIClient, MCPSharedState, ProcessSupervisor, ExecutionController, ToolSchemaCatalog, ecc.)
**Problema**: Almeno 15+ `NSLock` usati per proteggere stato condiviso. Alcuni sono su path caldi (ExecutionController.lock, ToolSchemaCatalog.lock). Nessun profiling di contention visibile.
**Impatto**: Potenziale contention non diagnosticata sotto carico.
**Fix suggerito**: Aggiungere metriche di contention (os_signpost) sui lock dei path caldi per identificare quelli effettivamente contesi.

---

## BOTTLENECK-12 — ChatPanelView rootLayout accede a store multipli nel body
**Stato**: **Parzialmente mitigato**: visibilità strip swarm e chrome loading usano snapshot `@State` (`snapshotRootLayoutSwarmSteps`, `snapshotRootLayoutSwarmCards`, `snapshotChromeLoading`) aggiornati in `refreshMessagesSnapshot`; fascia estratta in `ChatPanelRootSwarmProgressSlot`. Restano letture store dove necessario (`scopedTaskActivities`, `TaskControlBar`, `chatStore` nei pannelli).
**File**: `ChatPanelView+RootLayout.swift`, `ChatPanelView+PartC_MessageScrollState.swift`, `ChatPanelRootSwarmProgressSlot.swift`

---

## Riepilogo per Priorità

| Priorità | ID | Area | Impatto |
|----------|----|------|---------|
| P2 | BOTTLENECK-01 | Hybrid search sync legacy | Semaforo solo se si usa `search()` hybrid diretto |
| P1 | BOTTLENECK-02 | SemanticIndex Persist | I/O + memoria eccessiva |
| — | BOTTLENECK-03 | recalcAvgDocLength | **Mitigato** (O(1) in codice) |
| — | BOTTLENECK-04 | evictIfNeeded | **Migliorato** (no full sort) |
| P1 | BOTTLENECK-05 | ChatPanelView re-render | UI lag / frame drop |
| P1 | BOTTLENECK-06 | RustBridge full serialize | CPU + memoria (debounce + cache + signpost) |
| P2 | BOTTLENECK-07 | PipelineService @Published | Re-render extra |
| P2 | BOTTLENECK-08 | EventBus delivery | Latenza delivery |
| P2 | BOTTLENECK-09 | firstIndex O(n) | Lookup lento ripetuto |
| P2 | BOTTLENECK-10 | SequenceGenerator actor | Serializzazione eventi |
| P2 | BOTTLENECK-11 | NSLock non profilati | Contention nascosta |
| P2 | BOTTLENECK-12 | rootLayout store access | Re-render UI |
