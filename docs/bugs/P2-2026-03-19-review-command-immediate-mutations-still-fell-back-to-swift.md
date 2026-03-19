# P2 - Le mutazioni immediate del command loop review ricadevano ancora in Swift

## Bug Fix Record
- Categoria: B
- Bug: il command loop review usava gia' il planner e il mutator Rust, ma su `configure`, `dismiss`, `comment` e sulle mutate live/persisted continuava ad avere fallback semantici locali in Swift.
- Sintomo: `configuredReviewSnapshot(...)`, `applyReviewMutation(...)`, `mutateReviewSnapshot(...)` e `ReviewSessionRegistry.updateConfig(...)` potevano ancora ricreare localmente l’effetto del command anche quando il boundary Rust era il path primario.
- Impatto: la tranche 3 non era ancora Rust-first sul command bus immediato; persisteva rischio di drift tra mutator Rust e logica Swift di backup.
- Gravita': media-alta, perche' tocca command lifecycle, stato condiviso e persistenza snapshot live/persistita.
- Steps to reproduce:
  1. Queueare un `configure`, `dismiss` o `comment`.
  2. Seguire il path `CodigoApp+CodeReviewCommands -> CodigoApp+CodeReviewCommandMutations`.
  3. Verificare che su assenza/failure del mutator Rust il codice ricostruisce ancora l’effetto in Swift.
- Risultato attuale: il command bus review immediato non e' ancora realmente Rust-first.
- Risultato atteso: `configure`, `dismiss` e `comment` devono passare solo dal mutator Rust; se il review core non risponde, il command fallisce esplicitamente.
- Causa probabile: i fallback locali erano stati mantenuti per contenere il rischio nelle tranche iniziali del cutover.
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommands.swift`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommandMutations.swift`
  - `App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift`
  - `Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionRegistry.swift`
  - `Tests/SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests.swift`
  - `Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - `start` deferred command
  - patch workflow completo
  - MCP read ownership
  - MCP mutate/enqueue ownership
- Moduli confinanti da verificare:
  - `CodigoAppCodeReviewCommandLoopTests`
  - `MCPSharedCodeReviewCommandsTests`
  - mutator Rust `review_core_command_mutate_snapshot`
- Test da aggiungere o aggiornare:
  - success test Rust-first per `configure`, `dismiss`, `comment`
  - failure test con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1` per `configure` persistito
- Strategia di fix minimo:
  - rimuovere i fallback Swift da `configuredReviewSnapshot(...)`
  - far usare a `applyReviewMutation(...)` solo il mutator Rust anche sul path live
  - rimuovere il fallback locale di `mutateReviewSnapshot(...)`
  - far fallire `ReviewSessionRegistry.updateConfig(...)` se il mutator Rust non risponde
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testDismissCommandUsesRustPlannerAndPersistsWontFix -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testCommentCommandUsesRustMutationAndAppendsComment`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
- Commit previsto: `refactor(review-command): require rust mutator for immediate review commands`

## Effetto osservato
- Il command bus review immediato non ricostruisce piu' localmente `configure`, `dismiss`, `comment`.
- Il fallback locale resta solo nel caso esplicito di runtime Rust disabilitato, dove il command fallisce invece di divergere silenziosamente.
