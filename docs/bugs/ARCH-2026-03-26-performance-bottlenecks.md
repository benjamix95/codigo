# Performance Bottlenecks — Analisi Architetturale 2026-03-26

## Sommario

Analisi sistematica dei colli di bottiglia di performance nel progetto SoloCode.
Classificati per gravità: **P0** (critico), **P1** (importante), **P2** (moderato), **P3** (minore).

---

## P0 — Colli di Bottiglia Critici

### 1. HybridSearchEngineBackend: Semaphore blocking + Thread spawn per ogni ricerca

**File:** `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift:83-127`

**Problema:** `mergeWithVectorSync()` crea un **nuovo `Thread`** e **due `DispatchSemaphore`** per OGNI ricerca ibrida. Il thread blocca con `semaphore.wait(timeout: 2.0)` — potenziale deadlock se il cooperative pool di Swift è saturo. Ogni search spawna un thread OS dedicato (costo ~1MB di stack).

**Impatto:** ALTO — latenza ricerca +200-2000ms, rischio deadlock sotto carico, spreco memoria per thread stack.

**Suggerimento:**
- Rendere `search()` async nel protocollo `SearchEngineBackend`
- Eliminare il bridge sync→async e usare `TaskGroup` per parallelizzare lexical + vector
- Se il protocollo sync è necessario, usare un pool di thread riutilizzabili anziché spawn per-call

---

### 2. SemanticIndex `persist()`: Serializzazione completa ad ogni update

**File:** `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift:37-81`

**Problema:** `persist()` serializza **TUTTI i chunk** ordinandoli (`chunks.values.sorted`), li codifica uno a uno in JSON, li unisce con `\n` e scrive il file intero. Con 50K chunk (il limite configurato), questo significa:
- Sort O(n log n) su 50K elementi
- 50K encode JSON individuali
- Concatenazione stringa gigante
- Scrittura atomica del file completo

Il debounce a 2 secondi mitiga parzialmente, ma sotto aggiornamenti continui (file watcher) il costo è O(n) per ogni persist.

**Impatto:** ALTO — picchi di CPU e I/O di 500ms-2s durante persist, blocca l'actor SemanticIndex.

**Suggerimento:**
- Implementare persistenza incrementale (append-only log + compaction periodica)
- Persistere solo i chunk modificati dall'ultimo persist
- Usare formato binario (MessagePack/FlatBuffers) anziché JSON line-by-line

---

### 3. Rust scoring: Re-tokenizzazione O(n) per negative query

**File:** `Native/RustCore/src/scoring.rs:150-163`

**Problema:** Per query con token negativi (`-term`), il codice ri-tokenizza `contextualized_text` di **ogni chunk** che ha un punteggio — `tokenize_query(&chunk.contextualized_text)` dentro `scores.retain()`. Se ci sono 10K chunk con score, sono 10K tokenizzazioni.

**Impatto:** ALTO — latenza ricerca 10x-100x con query negative, CPU spike.

**Suggerimento:**
- Pre-computare i token per chunk al momento dell'indicizzazione e salvarli nello snapshot
- Usare l'inverted index per filtrare i negativi (lookup O(1) per token) anziché scan lineare

---

## P1 — Colli di Bottiglia Importanti

### 4. PipelineIntegrationService: `persistSnapshot()` chiamato ad ogni evento

**File:** `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift:325-356`

**Problema:** `persistSnapshot()` è chiamato su **ogni** evento pipeline: `jobStarted`, `jobCompleted`, `jobFailed`, `taskStarted`, `taskCompleted`, `handleProgress`, `handleCircuitBreaker`. Con task multipli e stream di testo ad alta frequenza, questo genera decine di snapshot/secondo. Ogni snapshot copia l'intero stato del runtime.

Il meccanismo di coalescing (`scheduleSnapshotFlush` via `DispatchQueue.main.async`) mitiga parzialmente ma crea comunque overhead di scheduling.

**Impatto:** MEDIO-ALTO — pressione GC, allocazioni ripetute su main thread durante streaming.

**Suggerimento:**
- Throttle a max 4-8 flush/secondo con timer fisso anziché per-evento
- Usare dirty flags granulari (quale campo è cambiato) anziché snapshot completo
- Evitare flush per eventi ad alta frequenza come `progressUpdate`

---

### 5. ChatPanelView: 18 @EnvironmentObject + ~35 @State

**File:** `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift:1-180`

**Problema:** `ChatPanelView` osserva **18 EnvironmentObject** (`chatStore`, `todoStore`, `taskActivityStore`, etc.). Ogni `.objectWillChange` di qualunque store triggera un potenziale re-render del body. Anche con i snapshot cached (`messagesConversationSnapshot`, etc.), la catena di dependency SwiftUI è pesante.

Inoltre ~35 `@State` e 4 `@StateObject` contribuiscono al footprint di allocazione della view.

**Impatto:** MEDIO-ALTO — re-render idle a startup (~24 come documentato nel commento), UI jank durante streaming.

**Suggerimento:**
- Estrarre sotto-view con `@ObservedObject` mirato (solo lo store necessario)
- Usare `EquatableView` o `.equatable()` per cortocircuitare re-render
- Separare le subscription pesanti in view wrapper dedicate

---

### 6. ChatStore+RustBridge: Serializzazione round-trip Swift↔Rust per ogni azione

**File:** `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`

**Problema:** Ogni azione (`applyRustStoreAction`, `applyRustTaskRuntimeAction`, `applyPipelineEvent`) segue il pattern:
1. `snapshot(from: store)` — serializza TUTTE le conversazioni e messaggi in bridge structs
2. Invio a Rust via FFI
3. Rust processa e ritorna nuovo snapshot
4. `apply(snapshot:to:)` — deserializza e ricrea tutte le conversazioni

Per una chat con 50 conversazioni e 500 messaggi, ogni azione copia l'intero stato. Durante streaming con eventi multipli/secondo, il costo è moltiplicativo.

**Impatto:** MEDIO-ALTO — allocazioni O(conversations × messages) per ogni evento pipeline, pressione su ARC/GC.

**Suggerimento:**
- Implementare delta updates: inviare solo la conversazione/messaggio modificato
- Cache dello snapshot corrente lato Swift, aggiornare in-place
- Batch multiple azioni in una singola round-trip FFI

---

### 7. TodoStore: `saveTodos()` sincrono su main thread, chiamato 18+ volte per ciclo

**File:** `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift:58-69`

**Problema:** `saveTodos()` è chiamato da almeno 18 punti nel codice (mutazioni, lifecycle, plan execution). Ogni chiamata:
- Filtra `userVisibleTodos`
- Codifica in JSON
- Scrive su `UserDefaults` (sincrono)
- Chiama `syncToSharedState()`

Durante un job pipeline con 5 task, facilmente 10-15 `saveTodos()` in rapida successione.

**Impatto:** MEDIO — latenza accumulata su main thread, I/O UserDefaults ripetuto.

**Suggerimento:**
- Debounce saves (come fatto per SemanticIndex persist)
- Scrivere su UserDefaults in background
- Coalescing: accumulare mutazioni e salvare una volta sola a fine batch

---

## P2 — Colli di Bottiglia Moderati

### 8. EventBus: `pruneIdempotencyKeysInternal()` chiamato ad ogni `publish()`

**File:** `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift:141`

**Problema:** Ogni `publish()` invoca `pruneIdempotencyKeysInternal()`. Il throttle a 5 secondi (`pruneThrottleInterval`) mitiga, ma la chiamata stessa ha overhead (creazione `Date()`, confronto timestamp, branch). Con stream ad alta frequenza (100+ eventi/sec), anche il check rapido accumula costo.

**Impatto:** BASSO-MEDIO — overhead marginale per-evento, ma scalabile.

**Suggerimento:**
- Spostare pruning in un timer periodico separato anziché inline nel hot path di publish
- Usare contatore di eventi anziché timestamp per decidere quando prunare

---

### 9. SemanticIndex `buildIndex()`: Batch size fisso di 64 file

**File:** `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift:32-75`

**Problema:** Il batch size di 64 file per la costruzione dell'indice è fisso. Per progetti con migliaia di file, il costo è dominato dal `TaskGroup` che spawna 64 task concorrenti per batch, poi attende tutti prima del prossimo batch. Nessuna configurazione per adattarsi alle risorse disponibili.

Inoltre, `addChunks` è chiamato sequenzialmente dopo ogni batch, serializzando l'aggiornamento dell'indice.

**Impatto:** MEDIO — tempo di build dell'indice non ottimale, sotto-utilizzo CPU su macchine potenti.

**Suggerimento:**
- Rendere il batch size configurabile in base ai core disponibili
- Usare streaming pipeline (producer-consumer) anziché batch-and-wait

---

### 10. AgentWorkerEventBridge: Actor SequenceGenerator conteso

**File:** `Engine/CoderEngine/Sources/AgentPipeline/Bridge/AgentWorkerEventBridge.swift:12-17`

**Problema:** `SequenceGenerator` è un actor con un singolo metodo `next()`. Ogni evento (textDelta, textReplace, raw) richiede `await sequencer.next()`. Con stream ad alta frequenza da worker multipli, gli `await` si serializzano sull'actor, creando un punto di contesa.

**Impatto:** BASSO-MEDIO — bottleneck seriale per generazione sequence number.

**Suggerimento:**
- Usare `OSAtomicIncrement64` o `AtomicUInt64` (swift-atomics) anziché un actor
- Oppure `UnsafeAtomic` da `Synchronization` framework

---

### 11. PipelineIntegrationService+EventMapping: doppio record per ogni task lifecycle

**File:** `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift:99-155`

**Problema:** Per ogni `taskStarted` e `taskCompleted`, il codice chiama ENTRAMBI:
- `recordStructuredPipelineTaskActivity()` 
- `recordPipelineSwarmLifecycleActivity()`

Più `consumePipelineUIEvent()` e `swarmProgressStore?.markStarted/Completed`. Sono 4 operazioni di store per ogni evento task lifecycle — overhead ridondante.

**Impatto:** BASSO-MEDIO — allocazioni e store writes raddoppiati per lifecycle events.

**Suggerimento:**
- Unificare in un singolo record con metadata sufficiente per entrambi i consumer

---

## P3 — Colli di Bottiglia Minori

### 12. SemanticIndex+Build: `addChunks()` sequenziale dopo ogni batch

**File:** `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift:55-70`

**Problema:** Dopo ogni batch di 64 file processato in parallelo via `TaskGroup`, `addChunks()` viene chiamato sequenzialmente per ogni file del batch. Questo serializza l'aggiornamento dell'indice in-memory, vanificando parte del parallelismo della fase di parsing.

**Impatto:** BASSO — overhead marginale rispetto al costo I/O del parsing, ma sub-ottimale per batch grandi.

**Suggerimento:**
- Accumulare tutti i chunk del batch e chiamare `addChunks()` una volta sola con il batch completo
- Oppure usare un buffer di staging e flush periodico

---

### 13. PipelineIntegrationService: `scheduleSnapshotFlush` via `DispatchQueue.main.async` crea micro-scheduling overhead

**File:** `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift:340-356`

**Problema:** `scheduleSnapshotFlush()` usa `DispatchQueue.main.async` per coalescere i dirty snapshot. Ogni chiamata a `persistSnapshot()` inserisce un blocco nella main queue. Sotto streaming ad alta frequenza (50+ eventi/sec), questo genera decine di blocchi GCD accodati, ognuno con overhead di scheduling (~1-5μs), anche se poi coalescono grazie al `snapshotFlushScheduled` flag.

**Impatto:** BASSO — overhead misurabile solo con profiling, non percepibile dall'utente.

**Suggerimento:**
- Sostituire con timer fisso (es. `RunLoop.main.schedule(after: .now + 0.05)`)
- Oppure usare `Task { @MainActor }` con debounce esplicito

---

## Stato Fix

| # | Priorità | Area | Stato |
|---|----------|------|-------|
| 1 | P0 | HybridSearch Thread+Semaphore | **FIXATO** — Task.detached + 1 semaphore |
| 2 | P0 | SemanticIndex full persist | **FIXATO** — dirty tracking + early return |
| 3 | P0 | Rust negative query re-tokenize | **FIXATO** — inverted index lookup |
| 4 | P1 | persistSnapshot() per-evento | Differito — coalescing esistente sufficiente |
| 5 | P1 | ChatPanelView 18 @EnvironmentObject | Differito — snapshot caching già presente |
| 6 | P1 | RustBridge round-trip completo | Differito — richiede delta protocol FFI |
| 7 | P1 | TodoStore saveTodos sincrono | Differito — già mitigato con flock skip |
| 8 | P2 | EventBus prune inline | Differito — throttle 5s sufficiente |
| 9 | P2 | SemanticIndex batch size fisso | Differito — funzionale, non bloccante |
| 10 | P2 | SequenceGenerator actor conteso | Differito — impatto basso |
| 11 | P2 | Doppio record task lifecycle | Differito — refactor non urgente |
| 12 | P3 | addChunks sequenziale post-batch | Differito — overhead marginale |
| 13 | P3 | scheduleSnapshotFlush overhead | Differito — non percepibile |

---

## P3 — Colli di Bottiglia Minori

### 12. Rust `handle_search_request`: HashMap rebuild per ogni query

**File:** `Native/RustCore/src/scoring.rs:82-87`

**Problema:** `chunks_by_id` HashMap è ricostruita da zero per ogni request di ricerca, anche se lo snapshot non cambia. Per 50K chunk, il costo è ~1-2ms di allocazione.

**Suggerimento:** Cache del HashMap tra richieste con lo stesso snapshot hash.

---

### 13. `consumePipelineUIEvent` / `consumePipelineEvents` invocati 20+ volte per job

**File:** Vari in `PipelineIntegrationService+*.swift`

**Problema:** Ogni evento pipeline genera una o più chiamate a `consumePipelineEvents` che passa per il bridge Rust (`applyPipelineEvent`). Con il costo del round-trip FFI (P1 #6), il volume amplifica il problema.

**Suggerimento:** Batch multiple eventi pipeline prima di invocare il bridge Rust.

---

## Riepilogo Priorità

| ID | Severità | Area | Bottleneck |
|----|----------|------|-----------|
| 1 | **P0** | Search | HybridSearch: Thread+Semaphore per-call |
| 2 | **P0** | Index | SemanticIndex persist() full dump |
| 3 | **P0** | Search | Rust negative query re-tokenization O(n) |
| 4 | **P1** | Pipeline | persistSnapshot() per-event |
| 5 | **P1** | UI | ChatPanelView 18 EnvironmentObject |
| 6 | **P1** | Bridge | Swift↔Rust full snapshot round-trip |
| 7 | **P1** | Store | TodoStore saveTodos() sync on main |
| 8 | **P2** | Pipeline | EventBus prune inline in publish() |
| 9 | **P2** | Index | buildIndex batch size fisso |
| 10 | **P2** | Pipeline | SequenceGenerator actor contention |
| 11 | **P2** | Pipeline | Doppio record per task lifecycle |
| 12 | **P3** | Search | Rust HashMap rebuild per query |
| 13 | **P3** | Pipeline | Volume FFI round-trips |

---

## Prossimi Passi Raccomandati

1. **P0-1 (HybridSearch):** Rendere `SearchEngineBackend.search()` async — elimina semaphore e thread spawn
2. **P0-2 (Persist):** Implementare append-only persistence con dirty tracking
3. **P0-3 (Negative):** Pre-computare token set nello snapshot Rust
4. **P1-6 (Bridge):** Delta updates nel bridge Swift↔Rust — massimo impatto su throughput pipeline
5. **P1-7 (TodoStore):** Aggiungere debounce come per SemanticIndex
