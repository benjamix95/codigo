# Analisi Problemi di Progettazione e Colli di Bottiglia — SoloCode

**Data:** 2026-03-25
**Tipo:** Audit architetturale
**Gravità complessiva:** Alta

---

## Sommario Esecutivo

L'analisi ha identificato **7 problemi di progettazione critici** e **5 colli di bottiglia** significativi.
I problemi principali riguardano: God Object nella view principale, abuso di `@unchecked Sendable`,
overhead del bridge Swift-Rust, cascade di re-render SwiftUI, e file Rust ben oltre il limite di 300/500 righe.

---

## P0 — CRITICO

### 1. GOD VIEW: ChatPanelView (50+ extension files, 16 @EnvironmentObject)

**Categoria:** A — Critico (Design)
**Impatto:** Performance UI, manutenibilità, testabilità

**Evidenza:**
- `ChatPanelView` ha **50 file di estensione** (PartA → PartS, multipli per lettera)
- **16 @EnvironmentObject** iniettati nella view root
- **64 extension totali** su `ChatPanelView` nel codebase
- La view è un monolite: gestisce streaming, composer, plan, debug, code review, swarm, task activity, provider sync, tutto in un unico tipo

**Problemi concreti:**
1. **Cascade re-render**: ogni `@EnvironmentObject` che cambia causa `body` re-evaluation dell'intera gerarchia.
   Con 16 oggetti osservati, ogni token di streaming può triggerare rebuild di componenti non correlati
2. **Accoppiamento totale**: qualsiasi cambiamento a qualsiasi store impatta ChatPanelView
3. **Impossibile testare in isolamento**: serve mock di 16+ dipendenze
4. **Compilazione incrementale**: modificare qualsiasi Part* ricompila l'intera ChatPanelView

**File coinvolti:**
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift` (root)
- 50 file `ChatPanelView+Part*.swift` distribuiti in 9 cartelle diverse

**Soluzione proposta:**
Decomposizione in sotto-view indipendenti con injection mirata:
- `ChatStreamingView` (PartO, PartP, PartQ, PartR) → solo ChatStore + PipelineIntegrationService
- `ChatComposerView` (PartB, PartH, PartK, PartL) → solo ChatStore + composerState
- `ChatPlanView` (PartJ, PartK, PartM, PartN, PartO) → solo ChatStore + TodoStore + PlanState
- `ChatDebugView` (PartF, PartG, PartP) → solo DebugStore + TaskActivityStore
- `ChatTaskTraceView` (PartF, PartG) → solo TaskActivityStore + ToolTraceStore

---

### 2. ABUSO DI @unchecked Sendable (19 classi)

**Categoria:** A — Critico (Concorrenza)
**Impatto:** Race condition, crash, stato corrotto

**Evidenza:**
19 classi marcate `@unchecked Sendable` nel codebase Engine:
```
AgentWorkerEventBridge, ToolSchemaEntry, MCPNativeToolRegistry,
ExecutionController, CodeReviewMultiSwarmProvider, StreamCaptureState,
MCPTransportResources, StdoutReadState, ProcessBox, ManagedProcessHandle,
RustSearchFFIClient, CodexCLIProvider, ClaudeCLIProvider, KiloCLIProvider,
GeminiCLIProvider, ToolEnabledLLMProvider, AnthropicAPIProvider, OpenAIAPIProvider
```

**Problemi concreti:**
1. `@unchecked Sendable` bypassa completamente il controllo del compilatore sulla thread safety
2. `AgentWorkerEventBridge` ha stato mutabile (`isShutdown`) senza protezione concorrente —
   `shutdown()` e i metodi delegate possono essere chiamati da thread diversi
3. Tutti i provider LLM (`Codex`, `Claude`, `Gemini`, `OpenAI`, `Anthropic`) sono `@unchecked Sendable`
   con stato mutabile interno non protetto
4. `ExecutionController` è `ObservableObject` (main actor bound) E `@unchecked Sendable` — contraddizione

**Soluzione proposta:**
- Convertire `AgentWorkerEventBridge.isShutdown` in `actor` o usare `Atomic<Bool>`
- I provider LLM dovrebbero essere `actor` anziché `class @unchecked Sendable`
- `ExecutionController` → rimuovere `@unchecked Sendable` o isolarlo con `@MainActor`

---

### 3. OVERHEAD BRIDGE SWIFT-RUST SU OGNI OPERAZIONE

**Categoria:** A — Critico (Performance)
**Impatto:** Latenza streaming, consumo CPU, allocazioni memoria

**Evidenza:**
- `RustMainChatStoreAdapter` (405 righe) serializza l'intero snapshot dello store ad ogni operazione
- `applyRustStoreAction` → `normalizedRustStoreSnapshot()` → serializza TUTTE le conversazioni → FFI → deserializza
- `applyPipelineEvent` chiama `uiState(from:context:)` che include snapshot completo + runtime + task state
- `applyPipelineEvents` (batch) è disponibile ma non sempre usato
- `stripCoderideMarkers` passa attraverso FFI anche per operazioni regex semplici

**Flusso hot-path durante streaming:**
```
token arrives → handleTextDelta → consumePipelineUIEvent → applyPipelineEvent
→ uiState(from:context:) [SERIALIZE TUTTO] → FFI Rust → [DESERIALIZE] → apply(snapshot:to:)
```

**Per ogni token di streaming, viene serializzato e deserializzato l'intero stato dell'app.**

**Problemi concreti:**
1. O(N) rispetto al numero di conversazioni/messaggi per ogni singolo token
2. Allocazioni continue di stringhe JSON per FFI
3. `conversationSnapshot()` e `messageSnapshot()` creano copie profonde di ogni messaggio
4. Nessun delta/diff — sempre snapshot completo

**Soluzione proposta:**
- Implementare delta-based updates: inviare solo il diff al Rust core
- Cache dello snapshot con invalidazione: non ricalcolare se non è cambiato
- Per `stripCoderideMarkers`: usare il fallback Swift per stringhe corte (<1KB)
- Batch multiple pipeline events prima di applicare (già supportato ma sottoutilizzato)

---

## P1 — IMPORTANTE

### 4. CRESCITA ILLIMITATA seenIdempotencyKeys nell'EventBus

**Categoria:** B — Importante (Memory)
**Impatto:** Memory leak lento, degradazione performance nel tempo

**Evidenza:**
`EventBus` mantiene `seenIdempotencyKeys: [String: Date]` con limite di 10.000 chiavi.
Il pruning avviene solo durante `publish()` — se il bus è idle, le chiavi non vengono mai pulite.
Con streaming intenso (centinaia di token/sec), 10.000 chiavi si raggiungono rapidamente.

**File:** `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift:87-88`

---

### 5. CASCADE @Published SU DIZIONARI NELLO ChatStore

**Categoria:** B — Importante (Performance)
**Impatto:** Re-render non necessari, CPU waste

**Evidenza:**
ChatStore ha 5+ dizionari `@Published`:
- `taskStartDates: [UUID: Date]`
- `planBoards: [UUID: PlanBoard]`
- `draftTexts: [UUID: String]`
- `taskStatusTexts: [UUID: String]`
- `activeTaskConversationIds: Set<UUID>`

Ogni modifica a qualsiasi valore in qualsiasi dizionario triggera `objectWillChange` per TUTTI
gli observer. Con 16 `@EnvironmentObject` che osservano ChatStore, ogni cambio di status text
rebuilda l'intera ChatPanelView hierarchy.

Il throttling a 150ms mitiga ma non risolve il problema strutturale.

**Soluzione proposta:**
- Separare ChatStore in sotto-store specializzati (ChatTaskRuntimeStore, ChatDraftStore, ecc.)
- Usare `@Observable` (macro) per granularità per-property anziché per-object

---

### 6. PipelineIntegrationService — RESPONSABILITÀ MULTIPLE

**Categoria:** B — Importante (Design)
**Impatto:** Manutenibilità, testabilità, complessità cognitiva

**Evidenza:**
`PipelineIntegrationService` (330 righe + 330 righe EventSupport + 250+ righe in altre estensioni)
gestisce:
1. Esecuzione job pipeline
2. Cancellazione e teardown
3. Snapshot management
4. Event routing (19 tipi di evento)
5. Todo management (canonical + agent)
6. Plan step sync
7. Debug projection binding
8. Swarm progress tracking
9. Raw event forwarding
10. Assistant update projection

**Soluzione proposta:**
Estrarre handler specializzati:
- `PipelineJobExecutor` — esecuzione e lifecycle
- `PipelineTodoHandler` — sync todo da eventi
- `PipelineDebugProjection` — debug store binding
- `PipelineEventRouter` — routing e dispatching

---

### 7. FILE RUST OLTRE LIMITE (13 file > 500 righe)

**Categoria:** B — Importante (Manutenibilità)
**Impatto:** Violazione regola 300 righe, difficoltà di review e manutenzione

**File critici (>500 righe):**
| File | Righe | Azione |
|------|-------|--------|
| `debug_tools.rs` | 1331 | Spezzare in moduli per tipo di tool |
| `plan_state.rs` (RustCore) | 1078 | Separare state/mutations/queries |
| `claude.rs` | 1022 | Estrarre parsing, session, streaming |
| `codex_app_server.rs` | 991 | Estrarre protocol, session, streaming |
| `server_smoke.rs` | 819 | Separare test per feature |
| `apply.rs` | 804 | Estrarre validazione, applicazione, rollback |
| `review_tools.rs` | 794 | Spezzare per categoria di tool |
| `plan_state.rs` (MCP) | 752 | Separare state/handlers |
| `ui_tests.rs` | 690 | Separare per area funzionale |
| `plan_markdown.rs` | 688 | Estrarre parser, renderer, serializer |
| `reducer.rs` | 678 | Estrarre action handlers per tipo |
| `models.rs` (review_patch) | 656 | Separare domain/dto/conversion |
| `review_audit.rs` | 590 | Estrarre scanner, reporter, aggregator |

---

## P2 — COLLI DI BOTTIGLIA SPECIFICI

### 8. SERIALIZZAZIONE JSON SINCRONA SUL MAIN THREAD

**Evidenza:**
`ChatStorePersistence` serializza su una `DispatchQueue` dedicata, ma
`RustMainChatStoreAdapter.snapshot(from:)` e tutte le chiamate FFI avvengono
sincroni dal main thread (dentro metodi `@MainActor`).

**Impatto:** Jank UI durante conversazioni lunghe con molti messaggi.

---

### 9. THROTTLE STREAMING A 150ms — POSSIBILE PERCEZIONE LAGGY

**Evidenza:**
`ChatStoreCore.conversationsDidChange()` throttla a 150ms durante streaming.
`ChatPanelView.streamThrottleInterval = 0.020` (20ms) è molto più aggressivo.
I due intervalli non sono coordinati — possibile che il throttle dello store
nasconda aggiornamenti che la view si aspetta.

---

### 10. DEAD LETTER QUEUE CAPACITY (1000) SENZA ALERTING

**Evidenza:**
`DeadLetterQueue(capacity: 1000)` — quando raggiunge la capacità, gli eventi
vengono silenziosamente scartati. Nessun meccanismo di alerting o backpressure
verso il producer.

---

### 11. NESSUN CIRCUIT BREAKER SULLA FFI RUST

**Evidenza:**
Se il Rust core va in errore o diventa lento, non c'è circuit breaker.
`ReviewCoreBridge.call()` potrebbe bloccare il main thread indefinitamente
se la FFI si blocca.

---

### 12. CLIAccountLoginCoordinator — 6 DIZIONARI @Published PARALLELI

**Evidenza:**
```swift
@Published var isRunningByAccount: [UUID: Bool] = [:]
@Published var statusByAccount: [UUID: String] = [:]
@Published var authURLByAccount: [UUID: URL] = [:]
@Published var lastOutputByAccount: [UUID: String] = [:]
@Published var awaitingInputByAccount: [UUID: Bool] = [:]
@Published var deviceCodeByAccount: [UUID: String] = [:]
```
6 dizionari separati per lo stesso stato logico (account login state).
Ogni aggiornamento di un campo triggera 1 `objectWillChange`.
Aggiornare lo stato completo di un account = 6 notifiche separate.

**Soluzione:** Consolidare in `@Published var accountStates: [UUID: AccountLoginState]`

---

## Priorità di Intervento Consigliata

| # | Problema | Priorità | Effort | Impatto |
|---|----------|----------|--------|---------|
| 1 | God View ChatPanelView | P0 | Alto | Performance + Manutenibilità |
| 3 | Bridge Swift-Rust overhead | P0 | Alto | Performance streaming |
| 2 | @unchecked Sendable | P0 | Medio | Sicurezza concorrenza |
| 5 | Cascade @Published | P1 | Medio | Performance UI |
| 6 | PipelineIntegrationService SRP | P1 | Medio | Manutenibilità |
| 7 | File Rust oversize | P1 | Medio | Manutenibilità |
| 8 | FFI sincrona main thread | P1 | Medio | UI responsiveness |
| 12 | CLIAccountLoginCoordinator | P2 | Basso | Performance minore |
| 4 | EventBus idempotency growth | P2 | Basso | Memory slow leak |
| 9 | Throttle non coordinato | P2 | Basso | UX streaming |
| 10 | DLQ senza alerting | P2 | Basso | Osservabilità |
| 11 | No circuit breaker FFI | P2 | Basso | Resilienza |

---

## Metriche Codebase

- **File Swift App:** ~111.673 righe totali
- **File Swift Engine:** ~71.965 righe totali
- **File Rust Native:** ~48.599 righe totali
- **ChatPanelView extensions:** 50 file, ~64 extension declarations
- **@unchecked Sendable:** 19 classi
- **@Published dictionaries:** 23+ nel codebase
- **File Rust > 500 righe:** 13
- **File Swift > 500 righe:** 1 (ChatPanelSupport+UIHelpers.swift: 628)
