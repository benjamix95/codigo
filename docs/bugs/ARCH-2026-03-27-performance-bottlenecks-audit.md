# ARCH — Audit colli di bottiglia performance 2026-03-27

## Scope dell'audit

- Obiettivo: trovare colli di bottiglia misurabili o strutturalmente evidenti che riducono reattivita', throughput o scalabilita' dell'app.
- Perimetro consentito: analisi del runtime SwiftUI, del bridge Swift↔Rust, dell'indice semantico e dell'event pipeline.
- Non-scope: refactor funzionali, cambi di UX, fix di correttezza non direttamente collegati alle performance.
- Metodi usati:
  - benchmark esistente `CodebaseIndexIndexingBenchmarkSmokeTests`
  - harness Swift ad-hoc collegato al framework `CoderEngine` gia' buildato
  - lettura dei path caldi con signpost e store hot-path gia' presenti nel repository

## Benchmark locali

- Dataset sintetico: 300 file Swift.
- Harness ad-hoc: mediane su 3 run.
- Risultati:
  - full indexing: `1327 ms` median
  - incremental indexing: `79 ms` median
  - semantic search: `436 ms` median
- Variabilita' osservata:
  - full indexing: `[1323, 1341, 1327] ms`
  - incremental indexing: `[79, 77, 84] ms`
  - semantic search: `[517, 436, 352] ms`

## Finding prioritizzati

### P1 — `semantic_search` serializza l'intero snapshot a ogni query

- Categoria: B
- Sintomo: la query di ricerca semantica paga un costo fisso alto anche su dataset moderati.
- Evidenza:
  - `SemanticIndexSearchSnapshot` contiene l'intero indice in memoria: chunk, inverted index, term frequencies e doc lengths in [SearchEngineBackend.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SearchEngineBackend.swift#L58).
  - ogni ricerca costruisce `RustSearchSnapshotPayload(from: snapshot)`, codifica tutto con `JSONEncoder()` e poi converte in `String` prima della FFI in [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift#L65).
- Impatto: costo O(size of index) per query anche quando la query e' piccola; questo spiega bene una `semantic_search` mediana di `436 ms` su soli 300 file.
- Causa probabile: il bridge Rust lavora su snapshot completi invece che su strutture condivise o delta/query-only.
- Fix minimo consigliato:
  - mantenere l'indice nel lato Rust e passare solo la query;
  - in alternativa, introdurre snapshot cacheabile con fingerprint e payload riutilizzabile finche' l'indice non cambia.

### P1 — `ChatPanelView` continua a registrare troppe dipendenze SwiftUI

- Categoria: B
- Sintomo: re-render diffusi durante streaming, attivita' task, aggiornamenti trace e snapshot pipeline.
- Evidenza:
  - `ChatPanelView` osserva 16 `@EnvironmentObject` nello stesso root view in [ChatPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift#L9).
  - la stessa view mantiene anche un numero molto alto di `@State` e `@StateObject`, inclusi snapshot, overlay state e cache di streaming in [ChatPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift#L48).
  - il `rootLayout` continua a distribuire molti `@ObservedObject` a wrapper che espongono direttamente `content()` e legge path dinamici come `taskActivityStore.activities(for:)` e `chatStore.conversation(...)` nel body in [ChatPanelView+RootLayout.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift#L20).
- Impatto: body re-evaluation frequente sul path piu' caldo dell'app, con jank percettibile durante stream, task bar, swarm progress e trace updates.
- Causa probabile: isolamento solo parziale; i wrapper separano il file ma non il dependency graph.
- Fix minimo consigliato:
  - spostare le letture calde in snapshot `@State` realmente indipendenti;
  - far osservare ai sotto-componenti solo store dedicati e solo dati gia' derivati;
  - evitare che wrapper pass-through registrino piu' `@ObservedObject` del necessario.

### P1 — Il bridge `ChatStore` ↔ Rust continua a fare copie complete dello stato chat

- Categoria: B
- Sintomo: ogni mutazione della chat puo' avere costo proporzionale al numero di conversazioni e messaggi, non alla sola modifica.
- Evidenza:
  - `snapshot(from:)` serializza tutte le conversazioni e tutte le plan board in [RustMainChatStoreAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift#L32).
  - `apply(snapshot:to:)` ricostruisce tutte le conversazioni da zero e, nel path `preserveLocalMessages`, esegue merge lineari sui messaggi streaming in [RustMainChatStoreAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift#L42).
- Impatto: allocazioni e copia memoria alte durante streaming e pipeline UI intents; rischio di amplificare ogni delta testuale in lavoro non locale.
- Causa probabile: il protocollo bridge opera ancora a livello di snapshot intero invece che per delta/patch.
- Fix minimo consigliato:
  - introdurre intent delta-based per singola conversazione o singolo messaggio;
  - mantenere indice secondario per lookup conversazione e aggiornamento in-place.

### P2 — `PipelineIntegrationService` pubblica snapshot completi sul main actor

- Categoria: B
- Sintomo: l'aggiornamento dello stato pipeline puo' propagarsi alla UI anche quando cambia solo una parte del runtime.
- Evidenza:
  - `snapshotsByConversation` e' `@Published` in [PipelineIntegrationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift#L81).
  - `persistSnapshot` accumula dirty ids ma il flush finale sostituisce comunque l'intero valore della snapshot dentro `DispatchQueue.main.async` in [PipelineIntegrationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift#L355).
- Impatto: invalidazione SwiftUI extra sul main actor durante stream, task lifecycle e teardown.
- Causa probabile: il service e' disegnato come store observable globale invece che come publisher piu' granulare per conversazione.
- Fix minimo consigliato:
  - pubblicare per-conversation subject;
  - evitare `@Published` sul dizionario completo;
  - introdurre throttle temporale fisso, non solo coalescing per runloop turn.

### P2 — `TodoStore.saveTodos()` resta sincrono e serializza tutto a ogni mutazione

- Categoria: B
- Sintomo: operazioni todo multiple in un singolo job causano encode JSON e sync shared-state ripetuti.
- Evidenza:
  - `saveTodos()` serializza `userVisibleTodos`, scrive su `UserDefaults` e poi chiama `syncToSharedState()` in [TodoStore+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift#L68).
- Impatto: latenza cumulativa sul main thread durante workflow plan/todo, specialmente con mutazioni ravvicinate.
- Causa probabile: assenza di debounce o batching su persistenza locale.
- Fix minimo consigliato:
  - debounce della persistenza;
  - write-back asincrona;
  - flush immediato solo sui punti terminali davvero critici.

### P2 — `EventBus.publish` fa prune inline e consegna sequenziale

- Categoria: B
- Sintomo: throughput eventi peggiora all'aumentare di subscriber e volume di stream.
- Evidenza:
  - `publish(_:)` invoca `pruneIdempotencyKeysInternal` su ogni evento in [EventBus.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift#L135).
  - la consegna ai subscriber avviene in un `for` sequenziale con `await deliveryManager.deliver(...)` nello stesso file in [EventBus.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift#L187).
- Impatto: backpressure artificiale durante streaming ad alta frequenza e maggiore sensibilita' a subscriber lenti.
- Causa probabile: scelta conservativa di ordering/semplicita' nel bus.
- Fix minimo consigliato:
  - pruning separato dal hot path;
  - delivery concorrente per subscriber indipendenti.

### P2 — `SemanticIndex.persist()` mantiene un path di full rewrite ancora costoso

- Categoria: B
- Sintomo: quando scatta il fallback full rewrite, l'indice viene ancora ordinato, serializzato e riscritto integralmente.
- Evidenza:
  - il full rewrite ordina tutti i chunk, li encoda e li unisce in una singola stringa prima della write in [SemanticIndex+Persistence.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift#L39).
- Impatto: picchi CPU/I/O su rebuild iniziali, invalidazioni grandi o casi in cui i dirty chunk superano la soglia del path incrementale.
- Causa probabile: la persistenza incrementale copre solo una parte dei casi.
- Fix minimo consigliato:
  - compaction separata dal path interattivo;
  - chunked writer invece di `joined(separator:)` su blob unico;
  - formato on-disk meno costoso del JSONL test-oriented.

### P2 — Lookup lineari su `conversations.firstIndex(where:)` ancora diffusi

- Categoria: B
- Sintomo: molte mutazioni chat cercano la stessa conversazione con scan lineare sull'array.
- Evidenza:
  - esempio diretto in [ChatStoreConversations.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Conversations/ChatStoreConversations.swift#L151).
  - il pattern e' diffuso anche nei bridge Rust e nei checkpoint store.
- Impatto: costo cumulativo crescente con il numero di thread e di mutazioni per stream.
- Causa probabile: manca un indice secondario `conversationId -> array index`.
- Fix minimo consigliato:
  - introdurre una mappa secondaria aggiornata insieme all'array;
  - usare la mappa nei path caldi di mutazione.

## Priorita' operativa suggerita

1. eliminare il payload completo della `semantic_search`;
2. rendere delta-based il bridge `ChatStore` ↔ Rust;
3. ridurre il dependency graph effettivo del `ChatPanelView`;
4. granularizzare la pubblicazione di `PipelineIntegrationService`;
5. spostare fuori dal main-thread le persistenze todo e gli hot path secondari.

## Verifica eseguita

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
- harness Swift locale collegato a `CoderEngine.framework` per misurare:
  - full indexing
  - incremental indexing
  - semantic search

## Stato

- Nessun fix applicato in questo audit.
- Findings documentati per priorita' e pronti per essere trasformati in task isolati.
