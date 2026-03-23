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
