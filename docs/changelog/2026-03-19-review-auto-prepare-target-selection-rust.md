# 2026-03-19 - Review auto-prepare target selection via Rust

## Modifiche
- esteso [review_finalize.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_finalize.rs) con la selezione auto-prepare filtrabile per `origin`
- aggiunto il request model in [review_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_models.rs)
- esposto il boundary [review_core_select_auto_prepare_targets](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_core.rs)
- [ReviewPatchRuntimeFinalizationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift) ora usa solo il core Rust per `autoPrepareEligibleFindingIds(...)`
- migliorato il resolver del dylib nei test app-side in [SoloCodeAppCodeReviewCommandLoopTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift)

## Verifica eseguita
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled`

## Esito
- anche la selezione auto-prepare dei finding non e' piu' source of truth Swift
- i test app-side passano senza skip ambientali sul path positivo
