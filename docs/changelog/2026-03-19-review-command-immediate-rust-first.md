# 2026-03-19 - Review command immediate Rust-first

## Modifiche
- `configure` persistito usa solo `review_core_command_mutate_snapshot`; rimosso il fallback locale in `configuredReviewSnapshot(...)`
- `dismiss` e `comment` live/persistiti passano ora solo dal mutator Rust nel command loop
- `mutateReviewSnapshot(...)` non ricrea piu' in Swift le mutate `apply_fix`, `dismiss`, `comment`, `close_finding`
- `ReviewSessionRegistry.updateConfig(...)` non ricade piu' su `state.updateConfig(...)` se il mutator Rust non risponde
- il command loop review immediato fallisce esplicitamente quando il review core e' disabilitato o il mutator non e' disponibile

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testDismissCommandUsesRustPlannerAndPersistsWontFix -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testCommentCommandUsesRustMutationAndAppendsComment`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`

## Esito
- il command loop review immediato e' ora Rust-first su `configure`, `dismiss`, `comment`
- Swift mantiene il dispatch del `start` deferred e del patch workflow, ma non duplica piu' la semantica delle mutate immediate del command bus
- questo batch apre davvero la tranche 3, lasciando i passi successivi su `start`/session lifecycle e poi MCP ownership
