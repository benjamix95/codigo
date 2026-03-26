# Performance Bottlenecks Analysis — 2026-03-25

## Sommario

Analisi completa dei colli di bottiglia individuati nel progetto SoloCode, classificati per area e priorità.

---

## 1. PIPELINE / RUNTIME — Colli di bottiglia

### 1.1 [ALTO] persistSnapshot() chiamata troppo frequentemente
- **File**: `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift`
- **Occorrenze**: 11 chiamate in 4 file
- **Problema**: `persistSnapshot()` è invocata ad ogni singolo evento della pipeline (jobStarted, jobCompleted, taskStarted, taskCompleted, progress, circuitBreaker, retarget, teardown). Ogni chiamata aggiorna `snapshotsByConversation` che è `@Published`, triggerando rebuild SwiftUI.
- **Impatto**: Con 10+ task e ~5 eventi/task = 50+ snapshot update per job, ognuno causa un ciclo di rendering.
- **Fix suggerito**: Debounce/coalesce gli snapshot update con un timer (es. 100ms), oppure usare un dirty flag e flush periodico.

### 1.2 [ALTO] EventBus — actor serialization bottleneck
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift` (linee 135-155)
- **Problema**: Singolo actor serializza tutte le `publish()`. Dentro publish: filtra TUTTE le subscription (O(N)), valida, registra idempotency key, enqueue al delivery manager. Nessun yield point intermedio.
- **Impatto**: Con 50 subscription e 100 eventi/sec = 5.000 filter/sec. Coda di publish in attesa.
- **Fix suggerito**: Indicizzare le subscription per eventType/jobId → O(1) lookup.

### 1.3 [ALTO] Idempotency key pruning O(N) ad ogni publish
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift` (linee 224-233)
- **Problema**: `pruneIdempotencyKeysInternal()` chiamata ad ogni publish. Usa array lineare + `removeFirst()` che è O(N) (riallocazione).
- **Impatto**: Con 10.000 key tracciate e 100 eventi/sec = 100 operazioni O(10k)/sec.
- **Fix suggerito**: Sostituire con ring buffer o Deque per O(1) removeFirst.

### 1.4 [ALTO] Task group overhead per lock acquisition
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/Orchestrator/OrchestratorMainLoop+Scheduling.swift` (linee 32-44)
- **Problema**: Crea un TaskGroup con 2 subtask (lavoro + timeout) per OGNI tentativo di acquisizione lock, per OGNI task ready, ad ogni tick.
- **Impatto**: Con 100 task ready e tick 10Hz = 1.000 task group/sec con 2.000 subtask.
- **Fix suggerito**: Usare `withTimeout()` diretto o `Task.sleep` con cancellation, senza TaskGroup.

### 1.5 [MEDIO] EventDeliveryManager — waitingKeys removeFirst() O(N)
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventDeliveryManager.swift` (linea 140)
- **Problema**: `drainWaitingQueue()` usa array lineare; `removeFirst()` è O(N).
- **Fix suggerito**: Usare `Deque` da swift-collections.

### 1.6 [MEDIO] Orchestrator main loop — polling fisso 100ms
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/Orchestrator/OrchestratorMainLoop.swift` (linea 200)
- **Problema**: Tick fisso 10Hz con operazioni sequenziali: check timeout, backpressure, schedule, collect results, enforce timeouts, check terminal. Tutte sequenziali.
- **Fix suggerito**: Event-driven scheduler oppure parallelizzare fasi indipendenti.

### 1.7 [MEDIO] PendingRecords dictionary — crescita unbounded
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventDeliveryManager.swift` (linea 76)
- **Problema**: Nessun limite massimo. Con 100 eventi × 50 subscriber = 5.000 record simultanei, ognuno con l'intero evento.
- **Fix suggerito**: Aggiungere capacity limit e eviction policy.

---

## 2. UI / RENDERING — Colli di bottiglia

### 2.1 [ALTO] ChatPanelView — troppi @EnvironmentObject
- **File**: `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift`
- **Problema**: 17 `@EnvironmentObject` nello stesso view. Ogni modifica a qualsiasi store causa il ricalcolo del body dell'intera ChatPanelView e di tutti i sotto-view.
- **Impatto**: Rebuild completo della UI ad ogni singolo update di qualsiasi store.
- **Fix suggerito**: Estrarre sotto-view dedicate che osservano solo gli store necessari. Usare `@ObservedObject` solo dove serve.

### 2.2 [ALTO] ChatStore conversations — O(n) lookup ripetuti
- **File**: `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- **Occorrenze**: 9 `firstIndex(where:)` nel modulo Chat/StoreRust
- **Problema**: Ricerche lineari su array `conversations` e `messages` per trovare per ID. Chiamate su hot path durante streaming.
- **Impatto**: Con 50 conversazioni e messaggi frequenti, O(n) per ogni operazione.
- **Fix suggerito**: Mantenere un dizionario indicizzato `[UUID: Int]` per indice conversazione, aggiornato ad ogni mutazione.

### 2.3 [MEDIO] @Published cascata — 5 proprietà in ChatStore
- **File**: `App/SoloCodeApp/Sources/Services/ChatStore/Core/ChatStoreCore.swift`
- **Problema**: 5 `@Published` separate (`activeTaskConversationIds`, `taskStartDates`, `planBoards`, `draftTexts`, `taskStatusTexts`). Ogni modifica a una qualsiasi triggera `objectWillChange` → rebuild di TUTTI i view che osservano ChatStore.
- **Fix suggerito**: Consolidare in un singolo struct `TaskState` oppure usare `objectWillChange.send()` manuale con debounce.

### 2.4 [BASSO] SwarmProgressStore / TaskActivityStore — frequenza update
- **Problema**: Aggiornati ad ogni evento pipeline senza throttle.
- **Fix suggerito**: Debounce a 50-100ms per update UI.

---

## 3. ENGINE / CONCORRENZA — Colli di bottiglia

### 3.1 [ALTO] Subscription filter matching O(N·M)
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift` (linee 149-152)
- **Problema**: Per ogni evento, scansiona TUTTE le subscription e applica 3 confronti (eventTypes, jobId, taskId). Nessuna indicizzazione.
- **Fix suggerito**: Mantenere indici per eventType → Set<SubscriptionId>.

### 3.2 [MEDIO] BackpressureController — signal history trim O(N)
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/WorkerPool/BackpressureController.swift` (linee 29-30, 160)
- **Problema**: Array di 1.000 elementi, trimming con `removeFirst()` ad ogni attivazione.
- **Fix suggerito**: Ring buffer o circular array.

### 3.3 [MEDIO] ContextCache — LRU eviction O(N)
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/Context/ContextCache.swift` (linee 76-86)
- **Problema**: `values.min()` scan lineare per trovare LRU entry. Nessuna struttura dati ottimizzata.
- **Fix suggerito**: Doubly-linked list + HashMap per O(1) LRU.

### 3.4 [BASSO] DeadLetterQueue — FIFO eviction O(N)
- **File**: `Engine/CoderEngine/Sources/AgentPipeline/EventBus/DeadLetterQueue.swift` (linee 87-89)
- **Problema**: `removeFirst()` su array fino a 1.000 elementi.
- **Fix suggerito**: Deque o circular buffer.

---

## 4. RUST BRIDGE / SERIALIZZAZIONE — Colli di bottiglia

### 4.1 [ALTO] uuidString.lowercased() — 35 allocazioni ripetute
- **File**: `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridgeMessages.swift` (23 occorrenze), `RustMainChatStoreAdapter.swift` (11 occorrenze)
- **Problema**: Ogni conversione UUID→String→lowercased crea 2 allocazioni String. Ripetuto 35 volte nei percorsi di serializzazione, spesso per lo stesso UUID nello stesso ciclo.
- **Impatto**: In un round-trip snapshot con 50 conversazioni × 20 messaggi = migliaia di allocazioni String ridondanti.
- **Fix suggerito**: Cachare il valore lowercased una volta per UUID, oppure usare una estensione `UUID.lowercasedString` con cache.

### 4.2 [ALTO] snapshot() — copia completa dello stato ad ogni operazione
- **File**: `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`
- **Problema**: `snapshot(from:)` crea una copia completa di TUTTE le conversazioni, messaggi, planBoard ad ogni chiamata. Chiamata da `uiState()`, `applyRustStoreAction()`, `applyPipelineEvent()`, etc.
- **Impatto**: Con 50 conversazioni × 100 messaggi = deep copy di migliaia di struct ad ogni evento pipeline.
- **Fix suggerito**: Snapshot incrementale (dirty tracking) o COW con reference semantics per payload grandi.

### 4.3 [ALTO] Round-trip Swift→Rust→Swift per operazioni semplici
- **File**: `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- **Problema**: Anche operazioni semplici come `stripCoderideMarkers` fanno un round-trip completo: encode JSON Swift → FFI → decode Rust → process → encode JSON Rust → FFI → decode JSON Swift.
- **Impatto**: Overhead di serializzazione per una semplice regex replace.
- **Fix suggerito**: Per operazioni semplici, usare il fallback Swift direttamente. Riservare il bridge Rust per operazioni batch o computazionalmente costose.

### 4.4 [MEDIO] Conversioni multiple nello stesso ciclo
- **File**: `RustMainChatStoreAdapter.swift` — `conversationSnapshot()`, `messageSnapshot()`
- **Problema**: Dentro i loop di mapping, lo stesso UUID viene convertito in stringa multiple volte (conversation.id, threadRootConversationId, contextId, workspaceId).
- **Fix suggerito**: Pre-computare le stringhe UUID fuori dal loop e riusarle.

---

## Riepilogo per priorità

### Priorità ALTA (fix consigliato immediato)
| # | Area | Bottleneck | Impatto stimato |
|---|------|-----------|-----------------|
| 1 | Pipeline | persistSnapshot() 11 chiamate/job senza debounce | Rebuild UI eccessivi |
| 2 | EventBus | Actor serialization + O(N) filter matching | Throughput limitato |
| 3 | EventBus | Idempotency key pruning O(N) per publish | CPU waste |
| 4 | Orchestrator | TaskGroup overhead per lock (1000+/sec) | Task creation overhead |
| 5 | UI | ChatPanelView 17 @EnvironmentObject | Rebuild UI completi |
| 6 | UI | O(n) firstIndex 9 occorrenze su hot path | Latenza lookup |
| 7 | Rust Bridge | 35× uuidString.lowercased() allocazioni | String allocation |
| 8 | Rust Bridge | Full snapshot copy ad ogni operazione | Memory + CPU |
| 9 | Rust Bridge | Round-trip FFI per operazioni semplici | Latenza inutile |

### Priorità MEDIA
| # | Area | Bottleneck |
|---|------|-----------|
| 10 | EventBus | waitingKeys removeFirst() O(N) |
| 11 | Orchestrator | Polling fisso 100ms sequenziale |
| 12 | EventBus | PendingRecords crescita unbounded |
| 13 | ChatStore | 5 @Published separate → cascade |
| 14 | BackpressureCtrl | Signal history trim O(N) |
| 15 | ContextCache | LRU eviction O(N) scan |
| 16 | Rust Bridge | Conversioni UUID ripetute in loop |

### Priorità BASSA
| # | Area | Bottleneck |
|---|------|-----------|
| 17 | Store | SwarmProgress/TaskActivity update senza throttle |
| 18 | DLQ | FIFO eviction O(N) |

---

## Stima impatto complessivo

I bottleneck più critici sono concentrati in 3 aree:
1. **Event pipeline** (EventBus + DeliveryManager): serializzazione actor + O(N) su ogni publish limita il throughput a ~1000 eventi/sec
2. **UI rendering** (ChatPanelView + ChatStore): 17 @EnvironmentObject + snapshot @Published = rebuild completo ad ogni evento
3. **Rust bridge** (snapshot + UUID conversion): full-copy dello stato + 35 allocazioni ridondanti ad ogni round-trip

**Scenario worst-case**: un job con 10 task genera ~80 eventi. Ogni evento causa: publish O(N) → snapshot copy → @Published update → full UI rebuild. Latenza stimata: 50-200ms per evento in pipeline complessa.

**Quick wins** (massimo impatto con minimo sforzo):
1. Debounce `persistSnapshot()` → riduce rebuild UI del 90%
2. Cache `uuidString.lowercased()` → elimina ~35 allocazioni/ciclo
3. Indice subscription per eventType → O(1) publish routing
