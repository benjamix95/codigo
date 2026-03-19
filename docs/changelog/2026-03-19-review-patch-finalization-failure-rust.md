# 2026-03-19 - Review patch finalization failure reduction via Rust

## Modifiche
- esteso [apply.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_session/apply.rs) con l’operazione `mark_patch_prepare_failed`
- [ReviewPatchRuntimeFinalizationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift) delega ora al reducer session Rust il failure path di `prepare_patch`
- il command loop auto-prepare usa lo stesso reducer Rust anche quando il runtime patch fallisce durante la preparazione automatica

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable`

## Esito
- il patch finalization app-side non ricostruisce piu' in Swift lo stato di failure della patch preview
- il path d’errore e' ora allineato alla session mutation Rust
