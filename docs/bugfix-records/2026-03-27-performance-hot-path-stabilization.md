# Bug Fix Record — 2026-03-27 Performance Hot Path Stabilization

## Record 1
- Categoria: B — Importante ma non bloccante
- Bug: la chat root osservava store e servizio pipeline anche dove bastavano snapshot locali o wrapper pass-through.
- Sintomo: invalidazioni UI inutili durante stream, task activity e strip swarm.
- Impatto: re-render extra sul path più caldo dell'app.
- Gravità: alta lato UX/performance.
- Steps to reproduce:
  1. avviare una chat con streaming attivo;
  2. lasciare visibili task bar e swarm progress;
  3. osservare refresh frequenti del layout root.
- Risultato attuale: wrapper root e componenti hot (`TaskControlBar`, `SwarmProgressView`) si aggiornavano via store/service osservati più larghi del necessario.
- Risultato atteso: i componenti hot devono ricevere dati già derivati e ascoltare solo aggiornamenti mirati.
- Causa probabile: dipendenze SwiftUI registrate troppo in alto nel tree e broadcast pipeline globali.
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Root/**`
  - `App/SoloCodeApp/Sources/Swarm/**`
  - `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/**`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/**`
- Non-scope:
  - provider runtime
  - protocollo Rust main chat
- Moduli confinanti da verificare:
  - `ChatPanelView`
  - `TaskControlBar`
  - `SwarmProgressView`
  - `PipelineIntegrationService`
- Test da aggiungere o aggiornare:
  - `PipelineIntegrationSnapshotPublisherTests`
- Strategia di fix minimo:
  - rimuovere observer passivi dai wrapper root;
  - usare snapshot cached per task/swarm/pipeline nel root;
  - introdurre publisher pipeline mirato per conversation.
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotTests -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotPublisherTests`
- Commit previsto:
  - `perf(chat): reduce root hot-path invalidations`

## Record 2
- Categoria: B — Importante ma non bloccante
- Bug: `TodoStore.saveTodos()` sincronizzava troppo spesso anche la shared state MCP durante burst ravvicinati.
- Sintomo: write amplification su `todos.json` nei workflow plan/todo.
- Impatto: I/O superfluo e costo cumulativo evitabile.
- Gravità: media.
- Steps to reproduce:
  1. eseguire più mutazioni todo ravvicinate;
  2. osservare persistenza locale + sync shared state ripetute.
- Risultato attuale: ogni `saveTodos()` faceva subito `syncToSharedState`.
- Risultato atteso: `UserDefaults` immediato, shared state MCP coalesced.
- Causa probabile: assenza di debounce sul canale cross-process.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/**`
- Non-scope:
  - policy todo
  - UI todo
- Moduli confinanti da verificare:
  - `MCPSharedState`
  - `TodoStorePersistenceTests`
- Test da aggiungere o aggiornare:
  - reuse di `TodoStorePersistenceTests`
- Strategia di fix minimo:
  - debounce della sola sync shared state;
  - preservare immediata persistenza in `UserDefaults`.
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TodoStorePersistenceTests`
- Commit previsto:
  - `perf(todo): debounce shared state sync`

## Record 3
- Categoria: B — Importante ma non bloccante
- Bug: `EventBus` manteneva pruning sul publish path ed era rimasto monolitico oltre il limite dimensionale locale.
- Sintomo: overhead evitabile su publish e modulo troppo grosso per manutenzione.
- Impatto: performance e leggibilità peggiori sui burst eventi.
- Gravità: media.
- Steps to reproduce:
  1. pubblicare molti eventi con subscriber multipli;
  2. osservare pruning ricorrente e gestione meno chiara del lifecycle.
- Risultato attuale: pruning chiamato nel publish path e `EventBus.swift` sopra il limite dimensionale desiderato.
- Risultato atteso: pruning più conservativo e file separati per lifecycle/idempotency.
- Causa probabile: crescita incrementale del modulo senza separazione dei path caldi.
- Scope consentito:
  - `Engine/CoderEngine/Sources/AgentPipeline/EventBus/**`
- Non-scope:
  - delivery semantics
  - API pubblica dell'event bus
- Moduli confinanti da verificare:
  - `EventDeliveryManager`
  - `AgentWorkerEventBridge`
  - `EventBusTests`
- Test da aggiungere o aggiornare:
  - reuse di `EventBusTests`
  - reuse di `AgentWorkerEventBridgeTests`
- Strategia di fix minimo:
  - estrarre lifecycle/idempotency in file dedicato;
  - pruning lazy senza eviction extra aggressiva.
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/EventBusTests -only-testing:CoderEngineTests/AgentWorkerEventBridgeTests`
- Commit previsto:
  - `perf(eventbus): split lifecycle and reduce prune overhead`

## Stato
- Fix applicati e verificati per:
  - invalidazioni root chat e progress UI
  - sync todo su shared state
  - lifecycle/idempotency event bus
- Residual risk:
  - la riduzione del payload `ChatStore` <-> Rust resta area più ampia e non è stata trasformata in un refactor di protocollo in questa passata per mantenere il perimetro confinato.
