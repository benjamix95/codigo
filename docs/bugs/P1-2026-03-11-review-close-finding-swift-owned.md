# P1 — `close_finding` ancora governato da Swift nel review stack

## Sintomo
Il command bus review poteva accodare `close_finding`, ma la validazione e la chiusura effettiva del finding non erano possedute dal core Rust.

## Impatto
- rischio di drift tra queue validation e patch workflow runtime
- comportamento incoerente fra handler MCP, lifecycle service e snapshot persisted-only
- possibilità di marcare il comando come riuscito senza chiudere realmente il finding

## Fix applicato
- esteso `review_patch` con semantica Rust per `close_finding`
- aggiunta validazione nativa della chiudibilità in `queue_context` e `plan_execution`
- propagato il contesto necessario dal bridge Swift
- aggiornato `VerifiedFindingsPatchExecutionService` per eseguire lo step `close_finding`
- allineato il fallback `VerifiedFindingsLifecycleCommandService` allo stesso contratto

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`
