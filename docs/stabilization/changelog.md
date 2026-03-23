# Stabilization Changelog

## 2026-03-23

### Session bootstrap
- Avviata la tranche di stabilizzazione per:
  - fail-fast DAG e sequencing eventi della pipeline
  - teardown idempotente del runtime chat pipeline
  - cleanup sessioni provider e processi child Rust
  - throughput `EventBus` e `DagScheduler`
  - documentazione tecnica di bug register e changelog di stabilizzazione

### Note operative
- Worktree iniziale già sporco; staging e commit devono restare confinati ai file toccati da questa stabilizzazione.
- Due finding originari esclusi dalla tranche critica perché già corretti nel codice corrente:
  - failover rate-limit presente su `claude`, `codex`, `gemini`
  - pruning delle idempotency key già presente in `EventBus`

### Implementato
- `PipelineFacade` ora fallisce subito su DAG invalido, senza `try?` silenziosi su add/validate.
- `AgentWorkerEventBridge` usa un generatore actor-backed per le sequence degli eventi streaming.
- `ProviderRegistry` mantiene un indice O(1) per `provider(for:)`.
- `EventBus` delega la delivery non bloccante a `EventDeliveryManager`, che ora esegue retry in task separati e cap il log dei tentativi.
- `DagScheduler` mantiene ready set e contatori incrementali invece di rifare scan completi per conteggi e readiness.
- `PipelineIntegrationService` ha teardown idempotente e `discardConversationRuntime` smette di lasciare snapshot/task state pendenti nel layer UI.
- `PipelineIntegrationService+ChatPipeline` coalesca `textDelta/textReplace` consecutivi nello stesso batch.
- `PipelineIntegrationService+EventSupport` normalizza una sola volta i raw events.
- `session.rs` usa `AtomicBool`, pulisce stato globale su cancel/terminal path e riduce il busy polling con backoff.
- `codex_app_server.rs` protegge il child process con una guardia RAII anche nei path di errore anticipato.

### Test eseguiti
- `cd /Users/benjaminstoica/SoloCode/Native/RustCore && cargo test session_tests -- --nocapture`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -only-testing:CoderEngineTests/AgentWorkerEventBridgeTests -only-testing:CoderEngineTests/PipelineFacadeTests -only-testing:CoderEngineTests/EventBusTests -only-testing:CoderEngineTests/EventDeliveryManagerTests -only-testing:CoderEngineTests/DagSchedulerTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationLifecycleTests`

### Residuo dichiarato
- La tranche strutturale sui file oversized e sull’estrazione dei boundary `ChatPanelView`/`ChatStore`/`TaskActivityStore` non è ancora chiusa in questo commit.

### Tranche successiva implementata
- aggiunto il path batch `pipeline_apply_events` tra `PipelineIntegrationService+ChatPipeline`, `RustMainChatStoreAdapter`, `MainChatUIIntentRequestBridge` e `main_chat/ui_intents.rs`
- mantenuto il fallback single-event compatibile
- aggiunti test Rust sul path batch UI e test Swift che verificano il coalescing fino allo snapshot chat finale
- modularizzato `runtime_transport.rs` in:
  - `runtime_transport/provider_resolution.rs`
  - `runtime_transport/transport_policy.rs`
- mantenuti invariati i risultati del routing provider/backend/multi-account tramite test di parità

### Nota strutturale
- i tentativi di split fisico dei grossi file Swift sono stati ricondotti a una versione compatibile con il wiring attuale del progetto Xcode: i percorsi legacy restano ancora i punti di compilazione attivi finché non viene aggiornata esplicitamente la membership dei nuovi file nel progetto.

### Test eseguiti per la tranche batch/modularization
- `cd /Users/benjaminstoica/SoloCode/Native/RustCore && cargo test ui_tests -- --nocapture`
- `cd /Users/benjaminstoica/SoloCode/Native/RustCore && cargo test runtime_transport -- --nocapture`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -only-testing:CoderEngineTests/EventBusTests -only-testing:CoderEngineTests/EventDeliveryManagerTests -only-testing:CoderEngineTests/PipelineFacadeTests -only-testing:CoderEngineTests/AgentWorkerEventBridgeTests -only-testing:CoderEngineTests/DagSchedulerTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationLifecycleTests -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests -only-testing:SoloCodeAppTests/SwarmProgressStoreTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
