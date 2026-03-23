# P2 - Il command `review_start` costruiva ancora il prompt in Swift

## Bug Fix Record
- Categoria: B
- Bug: dopo il batch sui command immediati review, il command loop continuava a costruire localmente in Swift il prompt del `start`, mantenendo una seconda semantica fuori dal review core Rust.
- Sintomo: `SoloCodeApp+CodeReviewCommands.swift` decideva ancora il testo del prompt per `scope=uncommitted|staged|against_ref`, compresi `review_prompt_override`, `bughunter_prompt_override`, `analysis_only` e `max_rounds`.
- Impatto: il command bus review non era ancora chiudibile come Rust-first, perché il `start` deferred manteneva nel layer app-side una decisione di dominio sulla forma del prompt.
- Gravita': media.
- Steps to reproduce:
  1. Queueare un `review_start`.
  2. Seguire il path `startReviewFromCommand(...)`.
  3. Verificare che il prompt viene ancora calcolato in Swift invece che dal review core Rust.
- Risultato attuale: il planner e il mutator sono Rust-backed, ma il `start` costruisce ancora il prompt in Swift.
- Risultato atteso: anche il prompt del `start` deve essere derivato dal review core Rust; se il review core non e' disponibile, il command deve fallire esplicitamente invece di ricadere su una semantica locale.
- Causa probabile: il prompt del `start` era rimasto nel layer `SoloCodeApp` per evitare di introdurre un nuovo boundary Rust nelle tranche iniziali.
- Scope consentito:
  - `Native/RustCore/src/review_command/*`
  - `Native/RustCore/src/ffi/review_command.rs`
  - `App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommands.swift`
  - `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - patch workflow
  - MCP read ownership
  - MCP mutate/enqueue ownership
  - persistenza thread/panel runtime
- Moduli confinanti da verificare:
  - `SoloCodeAppCodeReviewCommandLoopTests`
  - prompt builder Rust del `review_command`
  - `ReviewCommandRustBridge`
- Test da aggiungere o aggiornare:
  - unit test Rust sul prompt builder `staged`, `against_ref`, override espliciti
  - test app-side che `review_start` fallisce con runtime Rust disabilitato
  - test deferred start esistente reso esplicito sul prerequisito review core
- Strategia di fix minimo:
  - introdurre un nuovo boundary Rust `review_core_command_build_start_prompt`
  - instradare `startReviewFromCommand(...)` su quel boundary
  - rimuovere il costruttore locale `reviewPrompt(...)`
  - fallire esplicitamente quando il prompt Rust non è disponibile
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testStartCommandRemainsProcessingUntilDeferredReviewCompletes -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testStartCommandFailsWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testDeferredReviewMarksCommandFailedWhenSessionFails -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testDismissCommandUsesRustPlannerAndPersistsWontFix -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testCommentCommandUsesRustMutationAndAppendsComment`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
- Commit previsto: `refactor(review-command): route start prompt through rust runtime`

## Effetto osservato
- Il `start` deferred non porta più una seconda semantica prompt nel layer `SoloCodeApp`.
- Con questo batch il command loop review può essere trattato come Rust-first su planner, immediate mutations e start prompt; Swift resta soltanto execution bridge del deferred run.
