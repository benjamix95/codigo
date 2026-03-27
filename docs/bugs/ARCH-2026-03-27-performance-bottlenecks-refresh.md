# ARCH — Audit performance refresh 2026-03-27

## Scope

- Obiettivo: confermare con misure locali quali colli di bottiglia riducono ancora reattivita', throughput o scalabilita' dell'app.
- Perimetro consentito: runtime chat SwiftUI, bridge Swift <-> Rust, pipeline snapshot/eventi, persistenza todo, semantic index.
- Non-scope: refactor, nuove feature, fix funzionali non strettamente legati a performance.

## Misure eseguite

- Benchmark indicizzazione:
  - comando: `scripts/benchmark_indexing_pre_post.sh --phase post --tag PERF-AUDIT-20260327`
  - artefatto: `/Users/benjaminstoica/SoloCode/docs/benchmarks/indexing-hardening/PERF-AUDIT-20260327-post.json`
  - risultato:
    - `full_median_ms = 445`
    - `full_p95_ms = 452`
    - `incremental_median_ms = 8`
    - `incremental_p95_ms = 9`
- Benchmark review/runtime:
  - comando: `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag PERF-AUDIT-20260327`
  - artefatti:
    - `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/PERF-AUDIT-20260327-post-engine.json`
    - `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/PERF-AUDIT-20260327-post-app.json`
  - risultato engine:
    - `verified_sync_p95_ms = 10.612`
    - `historical_shape_p95_ms = 4.312`
    - `projection_build_p95_ms = 0.971`
    - `security_gate_p95_ms = 1.988`
  - risultato app:
    - `snapshot_ingest_p95_ms = 0.076`
    - `history_load_p95_ms = 0.632`
    - `main_thread_block_time_ms = 0.965`

## Sintesi

- L'indicizzazione incrementale attuale e' veloce; non emerge come collo di bottiglia primario dell'uso interattivo.
- La review core smoke e la proiezione app risultano leggere; non sono oggi il primo candidato per jank percepito.
- I problemi residui piu' concreti sono concentrati nella chat runtime/UI:
  - dependency graph SwiftUI ancora troppo ampio nel root view;
  - copie di stato ancora larghe nel bridge `ChatStore` <-> Rust;
  - snapshot pipeline pubblicati con granulosita' troppo grossa;
  - persistenze sincrone su path frequenti;
  - delivery eventi ancora seriale.

## Findings prioritizzati

### P1 — `ChatPanelView` resta il path UI piu' fragile e costoso

- Categoria: B
- Bug: il root della chat continua a registrare troppe dipendenze SwiftUI e propaga osservazioni ampie anche dove sono gia' presenti snapshot locali.
- Sintomo: body re-evaluation frequenti durante stream, task activity, trace updates e cambi di pannello.
- Impatto: jank percettibile nella vista piu' calda dell'app, soprattutto mentre arrivano delta o aggiornamenti concorrenti.
- Gravita': alta lato UX/runtime.
- Steps to reproduce:
  1. aprire una conversazione con stream attivo;
  2. lasciare visibili task bar, trace o swarm progress;
  3. osservare il volume di aggiornamenti del root layout durante i delta.
- Risultato attuale: il root osserva 16 `@EnvironmentObject` e mantiene molti `@State` nella stessa `View`.
- Risultato atteso: il root dovrebbe osservare solo snapshot derivati e delegare il resto a sotto-componenti realmente isolati.
- Causa probabile: isolamento strutturale incompleto; i wrapper dividono i file ma non abbastanza il dependency graph.
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Root/**`
  - `App/SoloCodeApp/Sources/Services/Chat*/**`
- Non-scope:
  - provider runtime
  - review core
  - semantic index
- Moduli confinanti da verificare:
  - `TaskActivityStore`
  - `ToolTraceStore`
  - `SwarmProgressStore`
- Test da aggiungere o aggiornare:
  - benchmark/render smoke dedicato alla chat root
  - signpost/instrument sample su stream attivo
- Strategia di fix minimo:
  - ridurre gli `@EnvironmentObject` del root;
  - rimuovere wrapper pass-through che osservano store ma restituiscono solo `content()`;
  - passare a snapshot `@State` gia' derivati anche per activity/task chrome.
- Verifica post-fix:
  - campione Instruments sul root chat
  - smoke su stream testo + task bar + trace
- Commit previsto:
  - `perf(chat): reduce root view dependencies during streaming`
- Evidenza:
  - [ChatPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift#L9)
  - [ChatPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift#L48)
  - [ChatPanelView+RootLayout.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift#L20)
  - [ChatPanelView+RootLayout.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift#L80)
  - [ChatPanelView+RootLayout.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift#L166)

### P1 — Il bridge `ChatStore` <-> Rust esegue ancora snapshot larghi sul main actor

- Categoria: B
- Bug: molte azioni di store continuano a serializzare/applicare snapshot completi o scoped ma comunque larghi, sul path principale della chat.
- Sintomo: costo per mutazione proporzionale alla dimensione della conversazione o del sottoinsieme snapshotizzato, invece che al delta reale.
- Impatto: CPU e allocazioni evitabili durante stream, append messaggi, plan board sync e mutazioni di stato chat.
- Gravita': alta lato throughput chat.
- Steps to reproduce:
  1. usare una conversazione lunga con molti messaggi;
  2. innescare piu' mutazioni ravvicinate;
  3. osservare il bridge mentre costruisce snapshot per azione.
- Risultato attuale: il bridge continua a richiedere `snapshot(from:)` o snapshot scoped per molte operazioni.
- Risultato atteso: mutazioni chat delta-based e applicazione minima del solo record coinvolto.
- Causa probabile: il contratto bridge privilegia coerenza semplice rispetto a granularita' del payload.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**`
  - `App/SoloCodeApp/Sources/Services/ChatStore/**`
  - `Native/RustCore/src/main_chat/**`
- Non-scope:
  - UI styling
  - provider selection
- Moduli confinanti da verificare:
  - persistenza conversazioni
  - checkpoint store
  - plan boards
- Test da aggiungere o aggiornare:
  - regression test che valida mutazioni delta-based
  - benchmark su conversazione grande
- Strategia di fix minimo:
  - introdurre path mutator piu' stretti per append/update message;
  - evitare ricostruzioni complete quando il target e' gia' noto.
- Verifica post-fix:
  - smoke su stream lungo
  - benchmark su 1 thread con alta cardinalita' messaggi
- Commit previsto:
  - `perf(chat): narrow rust store bridge payloads`
- Evidenza:
  - [RustMainChatStoreAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift#L30)
  - [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift#L79)
  - [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift#L103)

### P2 — `PipelineIntegrationService` pubblica snapshot con granularita' troppo ampia

- Categoria: B
- Bug: lo stato pipeline verso la UI resta aggregato in `snapshotsByConversation`, un dizionario `@Published` aggiornato sul main actor.
- Sintomo: anche un singolo cambiamento conversazione puo' notificare subscriber che osservano la struttura globale.
- Impatto: costi di invalidazione extra e crescita non lineare se aumentano conversazioni attive o consumer UI.
- Gravita': media.
- Steps to reproduce:
  1. tenere aperte piu' conversazioni con attivita' pipeline;
  2. generare eventi su una sola conversazione;
  3. osservare gli observer legati al dizionario completo.
- Risultato attuale: `snapshotsByConversation` e' `@Published`; il flush batch gira su `DispatchQueue.main.async`.
- Risultato atteso: publisher o store piu' granulari per conversazione.
- Causa probabile: semplificazione del modello osservabile.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/**`
- Non-scope:
  - event mapping business logic
  - UI visuale non legata agli snapshot
- Moduli confinanti da verificare:
  - `ChatPanelView`
  - `TaskControlBar`
  - debug projection
- Test da aggiungere o aggiornare:
  - regression benchmark con piu' conversation runtime attivi
- Strategia di fix minimo:
  - store per-conversation osservabile;
  - publisher selettivi invece del dizionario globale.
- Verifica post-fix:
  - smoke multi-conversation
  - signpost su batch flush
- Commit previsto:
  - `perf(pipeline): publish per-conversation snapshots`
- Evidenza:
  - [PipelineIntegrationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift#L81)
  - [PipelineIntegrationService+Snapshots.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+Snapshots.swift#L55)
  - [PipelineIntegrationService+Snapshots.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+Snapshots.swift#L80)

### P2 — `EventBus.publish` resta seriale e fa pruning sul path caldo

- Categoria: B
- Bug: ogni publish esegue prune delle chiavi idempotenza e consegna i subscriber in serie.
- Sintomo: la latenza di un subscriber lento si propaga a tutti gli altri.
- Impatto: throughput peggiore nei burst di eventi streaming.
- Gravita': media.
- Scope consentito:
  - `Engine/CoderEngine/Sources/AgentPipeline/EventBus/**`
- Non-scope:
  - mapping UI
  - protocollo degli eventi
- Strategia di fix minimo:
  - pruning lazy/soglia;
  - delivery concorrente dove ordering per-subscriber non e' richiesto.
- Evidenza:
  - [EventBus.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift#L135)
  - [EventBus.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift#L162)
  - [EventBus.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift#L187)

### P2 — `TodoStore.saveTodos()` resta sincrono e persiste l'intero set

- Categoria: B
- Bug: ogni mutazione todo serializza tutti i todo visibili, scrive `UserDefaults` e sincronizza shared state.
- Sintomo: costo cumulativo su workflow plan/todo con mutazioni ravvicinate.
- Impatto: latenza extra sul main thread e write amplification.
- Gravita': media.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/**`
- Non-scope:
  - UI dei todo
  - policy di generazione
- Strategia di fix minimo:
  - debounce persist;
  - flush immediato solo su eventi terminali.
- Evidenza:
  - [TodoStore+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift#L69)
  - [TodoStore+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift#L114)

### P3 — Il full rewrite del `SemanticIndex` e' ancora costoso, ma non e' oggi il primo collo di bottiglia interattivo

- Categoria: B
- Bug: il fallback full rewrite ordina tutti i chunk e riscrive tutto l'indice.
- Sintomo: picchi CPU/I/O su rebuild iniziali o invalidazioni grandi.
- Impatto: piu' visibile su bootstrap/rebuild che sull'uso interattivo normale.
- Gravita': medio-bassa nel profilo attuale.
- Nota: i benchmark correnti mostrano che l'update incrementale e' gia' veloce (`8 ms` median), quindi la priorita' resta sotto i colli di bottiglia chat/UI.
- Evidenza:
  - [SemanticIndex+Persistence.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift#L39)
  - [SemanticIndex+Persistence.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift#L85)

## Bottleneck mitigati o de-prioritizzati

- Il vecchio costo di serializzazione completa per ogni semantic search e' in parte mitigato dalla cache `rustSnapshotJSON`, riutilizzata quando disponibile:
  - [SemanticIndex+Search.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Search.swift#L62)
  - [RustSearchFFIClient+Payload.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient+Payload.swift#L8)
- L'overhead actor per sequence generation negli eventi worker non e' piu' prioritario: il bridge usa `OSAllocatedUnfairLock` invece dell'actor precedente.
  - [AgentWorkerEventBridge.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Bridge/AgentWorkerEventBridge.swift#L11)
- Il review core smoke attuale non mostra main-thread block significativo.

## Priorita' operativa consigliata

1. Ridurre il dependency graph reale di `ChatPanelView`.
2. Rendere delta-based il bridge `ChatStore` <-> Rust per le mutazioni piu' frequenti.
3. Granularizzare `PipelineIntegrationService` per conversazione.
4. Debounce della persistenza todo.
5. Parallelizzare o alleggerire `EventBus.publish`.

## Stato

- Nessun fix codice applicato in questo audit.
- Benchmark e findings aggiornati e documentati.
