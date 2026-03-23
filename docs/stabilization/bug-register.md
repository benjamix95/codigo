# Stabilization Bug Register

Data di avvio: 2026-03-23

## P0

Nessun bug P0 registrato in questa tranche.

## P1

### P1-2026-03-23-agent-pipeline-fail-fast-and-lifecycle
- Stato: `fixed`
- Area: `AgentPipeline`, `ChatPipeline runtime`, `Rust providers`
- Sintomo:
  - DAG invalidi accettati fino al runtime.
  - Sequencing eventi worker non serializzato.
  - Finalizzazione pipeline non idempotente.
  - Sessioni provider e processi child non sempre puliti.
- File principali:
  - `/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Bridge/PipelineFacade.swift`
  - `/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Bridge/AgentWorkerEventBridge.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift`
  - `/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/session.rs`
  - `/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
- Rischio:
  - timeout e blocked tasks mascherano errori strutturali
  - duplicazione/ordine non deterministico degli eventi
  - leak di memoria e processi orfani
- Fix applicati:
  - fail-fast DAG in `PipelineFacade` con validazione dipendenze/cicli
  - sequence monotona actor-backed in `AgentWorkerEventBridge`
  - teardown idempotente in `PipelineIntegrationService`
  - `AtomicBool` + cleanup session/config + polling con backoff in `session.rs`
  - guard RAII child process in `codex_app_server.rs`
  - indice `id -> provider` in `ProviderRegistry`
- Verifica:
  - `cargo test session_tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -only-testing:CoderEngineTests/AgentWorkerEventBridgeTests -only-testing:CoderEngineTests/PipelineFacadeTests -only-testing:CoderEngineTests/EventBusTests -only-testing:CoderEngineTests/EventDeliveryManagerTests -only-testing:CoderEngineTests/DagSchedulerTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationLifecycleTests`

### P1-2026-03-23-agent-pipeline-throughput
- Stato: `partially_fixed`
- Area: `EventBus`, `DagScheduler`, `PipelineIntegrationService+ChatPipeline`
- Sintomo:
  - retry inline e fan-out seriale bloccano `publish`
  - scheduler con scan completo a tick
  - projection Rust/UI per-evento invece che per-batch
- File principali:
  - `/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventBus.swift`
  - `/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventDeliveryManager.swift`
  - `/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/AgentPipeline/Scheduler/DagScheduler.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+ChatPipeline.swift`
- Fix applicati:
  - `publish` non resta bloccato dai retry inline
  - cap del log tentativi delivery
  - `DagScheduler` con ready set e contatori incrementali
  - coalescing dei `textDelta/textReplace` nello stesso batch Swift
  - normalizzazione raw event singola nel path `EventSupport`
- Residuo:
  - manca ancora un batching nativo cross-call sul boundary Rust/UI
  - la tranche strutturale su file oversized resta aperta

## P2

### P2-2026-03-23-chat-ui-oversized-boundaries
- Stato: `pending`
- Area: `ChatPanelView`, `ChatPanelSupport`, `ChatStore Rust bridge`, `TaskActivityStore`
- Sintomo:
  - root view con stato esploso
  - support/god files oltre policy
  - sovrapposizione tra `TaskActivityStore`, `TodoStore`, `SwarmProgressStore`
- File principali:
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
