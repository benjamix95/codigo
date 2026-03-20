# P1 - Il direct stream e il plan multi-turn della main chat erano ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: il path live non-agent della `main chat` continuava a possedere in Swift watchdog, retry, auto-continuation e phase transitions del plan flow.
- Sintomo:
  - il coordinatore direct stream viveva ancora in un file Swift dedicato poi drenato in [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift)
  - [ChatPanelView+PartM_MultiTurn.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartM_MultiTurn.swift) e [ChatPanelView+PartM_Phase3.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartM_Phase3.swift) mutavano direttamente `planFlowPhase` e `planningState`
  - [ChatPanelView+PartN_Continuation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/ChatPanelView+PartN_Continuation.swift) costruiva ancora in Swift la continuation prompt
- Impatto: la tranche 2 del cutover `main chat -> Rust` restava bloccata nelle aree più fragili del runtime chat, con logica di orchestration e retry duplicata fuori dal core Rust.
- Gravita': alta, perche' tocca async streams, retry, plan orchestration e state management condiviso.
- Steps to reproduce:
  1. Aprire lo storico del path runtime chat o il codice attuale in [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift).
  2. Cercare i branch `watchdog=no_events`, `watchdog=stalled`, `continueIfPrematureStub`, `planFlowPhase =`.
  3. Verificare che state machine e prompt continuation vivano ancora nel layer Swift.
- Risultato attuale: il core Rust riduceva già gli eventi di turno, ma il runtime completo direct/plan restava Swift-owned.
- Risultato atteso: Swift deve limitarsi a projection e invocazione bridge; retry budget, continuation e plan runtime devono essere determinati dal core Rust.
- Causa probabile: la tranche 1 ha portato il reducer e il boundary base, ma non ancora la state machine di runtime non-agent.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_runtime.rs`
  - `Native/RustCore/src/main_chat/*`
  - `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift`
  - `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/Plan/*`
  - `App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineEvent.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - transport provider full-Rust
  - persistenza completa `ChatStore`
  - hard-fail definitivo dei prefissi `main-chat`
- Moduli confinanti da verificare:
  - `ConversationFlowCoordinatorTests`
  - `PlanFlowPhaseTests`
  - `PlanShortcutAndCommandTests`
  - `PlanBuildIntegrationFlowTests`
  - `ChatPipelineReducerTests`
- Test da aggiungere o aggiornare:
  - unit Rust su `stream_runtime`, `continuation`, `plan_runtime`
  - parity suite app-side sopra, se il runner macOS torna avviabile
- Strategia di fix minimo:
  - introdurre snapshot runtime condivisi `direct_stream` e `plan`
  - instradare timeout/retry/continuation via `chat_core_handle_action`
  - spostare in Rust la generazione dei prompt plan
  - usare Swift solo come adapter di provider/UI
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "$(git diff --name-only --diff-filter=ACMR | paste -sd, -)" --format text`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PlanFlowPhaseTests -only-testing:SoloCodeAppTests/PlanBuildIntegrationFlowTests`
- Commit previsto: `refactor(main-chat): move direct and plan runtime state into rust`

## Effetto osservato
- Il core Rust puo' ora possedere snapshot runtime `direct_stream` e `plan`.
- Il wiring Swift compila e il gate strutturale sui file realmente toccati e' verde.
- La tranche non e' ancora chiudibile finche' il runner test app-side continua a crashare in bootstrap.
