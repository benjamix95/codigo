# 2026-03-19 - Review configure bridge fail-closed

## Modifiche
- [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift) non ricostruisce piu' localmente `config/events/outcome` nel path `configuredReviewSnapshot(...)`.
- Il bridge accetta ora solo `mutation.snapshot` come risultato canonico del mutator Rust `configure`.

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift --format text`

## Esito
- il path `configure` review non mantiene piu' logica locale nel bridge app-side
- il comportamento fail-closed resta preservato
