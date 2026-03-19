# 2026-03-19 - Review panel command mutation fail-closed

## Modifiche
- [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift) accetta ora solo `mutation.snapshot` come success path di `review_core_command_mutate_snapshot`.
- È stato rimosso il fallback locale che ricostruiva `dismiss` e il fallback generico che riassemblava `findings/events/outcome` in Swift.
- [CodeReviewPanelSessionScopingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift) copre ora anche il fail-closed quando il runtime Rust è disabilitato.

## Verifica eseguita
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFailsClosedWhenRustMutationUnavailable`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift --format text`

## Esito
- il panel review non ricostruisce più localmente lo snapshot nel command mutation path
- il boundary review strict resta a zero violazioni
- il path `dismiss` lato panel è ora coerente con l'obiettivo fail-closed del cutover Rust
