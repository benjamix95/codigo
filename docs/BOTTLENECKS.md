# Analisi Colli di Bottiglia — SoloCode

**Data:** 2026-03-26  
**Scope:** Intero progetto (App Swift, Engine Swift, Native Rust)

---

## Legenda severità

| Livello | Significato |
|---------|-------------|
| 🔴 CRITICO | Impatto diretto su performance UI o stabilità runtime |
| 🟠 ALTO | Degrado misurabile, rischio di regressione |
| 🟡 MEDIO | Overhead evitabile, debito tecnico accumulato |
| 🟢 BASSO | Miglioramento opportunistico |

---

## 1. 🔴 File Rust oltre 500 righe (violazione regola progetto)

Questi file superano il limite massimo di 500 righe e devono essere spezzati:

| File | Righe | Eccesso | Azione suggerita |
|------|-------|---------|------------------|
| `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs` | **1377** | +877 | Spezzare in `codex_app_server_auth.rs`, `codex_app_server_streaming.rs`, `codex_app_server_events.rs` |
| `Native/RustCore/src/main_chat/providers/cli/claude.rs` | **1207** | +707 | Spezzare in `claude_auth.rs`, `claude_streaming.rs`, `claude_models.rs` |
| `Native/RustCore/src/plan_state.rs` | **1129** | +629 | Spezzare in `plan_state_core.rs`, `plan_state_mutations.rs`, `plan_state_serialization.rs` |
| `Native/RustCore/src/review_session/apply.rs` | **804** | +304 | Spezzare in `apply_core.rs`, `apply_validation.rs` |
| `Native/RustCore/src/main_chat/ui_tests.rs` | **690** | +190 | Spezzare per area funzionale testata |
| `Native/RustCore/src/main_chat/plan_markdown.rs` | **690** | +190 | Spezzare in `plan_markdown_render.rs`, `plan_markdown_parse.rs` |
| `Native/RustCore/src/main_chat/reducer.rs` | **678** | +178 | Spezzare per action type |
| `Native/RustCore/src/review_patch/models.rs` | **656** | +156 | Spezzare in `models_core.rs`, `models_bridge.rs` |
| `Native/RustCore/src/review_command/mutator.rs` | **524** | +24 | Minore, ma da monitorare |
| `Native/RustCore/src/review_pipeline/tasks.rs` | **517** | +17 | Minore, ma da monitorare |

**Impatto:** Manutenibilità ridotta, difficoltà nel testing isolato, rischio di regressioni in moduli monolitici.

---

## 2. 🔴 ChatPanelView Extension Sprawl — 14.539 LOC in 50+ file

`ChatPanelView` è frammentato in **50+ extension** per un totale di **~14.500 righe**.

### Problema architetturale
- La struct `ChatPanelView` ha **61 property wrapper reattivi** (@State, @EnvironmentObject, @StateObject, @Binding, @AppStorage)
- Ogni `@EnvironmentObject` registra la View come subscriber di quel store → **qualsiasi mutazione** su qualsiasi store trigga il ricalcolo del body
- 17 `@EnvironmentObject` × N mutazioni/secondo durante streaming = **cascata di re-render**

### File extension più grandi (>300 righe):
| File | Righe |
|------|-------|
| `ChatPanelView+PartL_SendMessage.swift` | 383 |
| `ChatPanelView+PartM_Phase3.swift` | 355 |
| `ChatPanelView+LifecycleModifiers.swift` | 335 |
| `ChatPanelView+PartF_DebugTodoEvents.swift` | 332 |
| `ChatPanelView+PartC_MessageHeader.swift` | 322 |
| `ChatPanelView+PartR_Rewind.swift` | 310 |
| `ChatPanelView+PartO_Streaming1.swift` | 310 |
| `ChatPanelView+PartF_AutoTodoRuntime.swift` | 300 |

### Impatto performance
- SwiftUI rivaluta l'intero body di ChatPanelView anche per mutazioni irrilevanti
- Gli snapshot cached (`messagesConversationSnapshot`, `snapshotIsLoading`) mitigano MA non eliminano il problema
- Durante streaming con pipeline attiva: stima **20-40 re-render/secondo** inutili

### Soluzione suggerita
Decomposizione in **child View dedicate** con solo gli store necessari iniettati, NON tutto l'environment. Esempio:
- `ChatMessagesListView` (solo chatStore, toolTraceStore)
- `ChatComposerContainerView` (solo chatStore, todoStore)
- `ChatTaskStatusView` (solo taskActivityStore, swarmProgressStore)

---

## 3. 🟠 FFI Bridge Overhead Swift ↔ Rust

### Percorso critico: `RustMainChatStoreAdapter.snapshot()` → Rust → `apply()`

Ogni pipeline event segue questo percorso:
1. `handleEvent()` → `consumePipelineEvents()` → `applyPipelineEvent()`
2. `applyPipelineEvent()` chiama `uiState(from: store, context:)` → **serializza TUTTE le conversazioni in bridge struct**
3. Rust processa l'evento
4. Swift deserializza lo snapshot e chiama `apply(snapshot:to:)` → **riscrive conversations/planBoards**

### Costo per evento
- `snapshot(from:)` itera **tutte le conversazioni** e **tutti i messaggi** per creare `MainChatStoreSnapshotBridge`
- Incluso: mapping di ogni `ChatMessage` → `MainChatStoreMessageSnapshotBridge` (con blocks, attachments, subagentCards, turnMetadata)
- A 20-50 eventi/secondo durante streaming → **20-50 snapshot completi/secondo**

### File coinvolti
- `RustMainChatStoreAdapter.swift` (407 righe) — serializzazione/deserializzazione
- `ChatStore+RustBridge.swift` (298 righe) — entry point bridge
- `MainChatStoreBridgeModels.swift` (403 righe) — modelli bridge

### Soluzione suggerita
- **Delta/incremental bridge**: inviare solo la conversazione modificata, non l'intero snapshot
- **Batch pipeline events**: già parzialmente implementato con `applyPipelineEvents()`, ma il singolo `applyPipelineEvent()` è ancora usato in molti path
- **Lazy serialization**: serializzare i messaggi on-demand, non upfront

---

## 4. 🟠 Pipeline Snapshot Copying ad ogni evento

### Percorso
`handleEvent()` → `persistSnapshot(for:)` → aggiorna `snapshotsByConversation[conversationId]`

- `PipelineConversationSnapshot` viene ricostruito/copiato ad ogni task event
- `flushSnapshotNow()` forza una pubblicazione immediata di `@Published snapshotsByConversation`
- Ogni pubblicazione trigga `objectWillChange` su `PipelineIntegrationService` → tutti i subscriber SwiftUI si aggiornano

### File coinvolti
- `PipelineIntegrationService.swift` (389 righe)
- `PipelineIntegrationService+EventMapping.swift` — chiama `persistSnapshot` per ogni task start/complete/fail

### Soluzione suggerita
- Throttle degli snapshot update (max 4-10/sec) come già fatto per `debugProjectionBufferRevision`
- Usare il pattern `dirtySnapshotConversationIds` + `snapshotFlushScheduled` già presente ma non attivo su tutti i path

---

## 5. 🟡 File Swift oltre 500 righe

| File | Righe |
|------|-------|
| `CodeReviewPanelStore.swift` | **515** |
| `PipelineIntegrationService+ChatPipeline.swift` | **481** |

Questi sono al limite. Monitorare e spezzare alla prossima modifica.

---

## 6. 🟡 TaskActivityStore: frequenza di update durante streaming

Ogni `textDelta` e `taskStarted/taskCompleted` chiama:
- `recordStructuredPipelineTaskActivity()` 
- `recordPipelineSwarmLifecycleActivity()`
- `recordPipelineSubagentTextActivity()`

Ciascuna aggiunge una `TaskActivity` allo store → `@Published` update → subscriber SwiftUI.

### File coinvolti
- `PipelineIntegrationService+EventMapping.swift` — 3 chiamate per ogni task event
- `TaskActivityStore+Query.swift` (409 righe)
- `TaskActivityStore+CodeReview.swift` (388 righe)

### Soluzione suggerita
- Batch le activity e flusharle con throttle (il `taskActivityFlushInterval: 0.1` è definito ma va verificato se è attivo)

---

## 7. 🟡 AgentWorkerEventBridge — Actor sequenziale

`SequenceGenerator` è un actor che serializza **ogni** evento per generare un sequence number:
```rust
private actor SequenceGenerator {
    private var nextValue: UInt64 = 0
    func next() -> UInt64 { ... }
}
```

Con alto throughput di delta, l'`await sequencer.next()` introduce hop tra actor che rallenta il publishing.

### Soluzione suggerita
Sostituire con `OSAtomicIncrement64` o `AtomicUInt64` (swift-atomics) per evitare l'actor hop.

---

## 8. 🟢 Caching mancante nel layer Rust

- `trigram/index.rs`, `trigram/search.rs`: ogni ricerca ricostruisce strutture; un LRU cache per query frequenti ridurrebbe il costo
- `scoring.rs`: ricalcola score senza memoizzazione
- `markers/sanitize.rs`: regex compilate ad ogni invocazione (verificare se `lazy_static`/`once_cell` è usato)

---

## Priorità di intervento raccomandata

| # | Intervento | Severità | Impatto stimato | Effort |
|---|-----------|----------|-----------------|--------|
| 1 | Decomposizione ChatPanelView in child views | 🔴 | -60% re-render idle | Alto |
| 2 | Delta bridge Swift↔Rust (solo conv modificata) | 🔴 | -80% overhead FFI | Alto |
| 3 | Spezzare file Rust >500 righe | 🔴 | Manutenibilità | Medio |
| 4 | Throttle pipeline snapshot publishing | 🟠 | -50% objectWillChange | Basso |
| 5 | Batch TaskActivity flush | 🟡 | -30% store churn | Basso |
| 6 | Atomics per SequenceGenerator | 🟡 | Elimina actor hop | Basso |
| 7 | LRU cache trigram/scoring Rust | 🟢 | Velocità ricerca | Medio |

---

*Generato automaticamente da analisi statica del codebase SoloCode.*
