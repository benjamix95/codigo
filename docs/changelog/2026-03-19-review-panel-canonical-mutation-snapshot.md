# 2026-03-19 - Review panel canonical mutation snapshot

## Modifiche
- [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift) decodifica ora `snapshot` in `ReviewPanelCommandMutationResponse`
- il panel runtime ingerisce direttamente lo snapshot canonico Rust quando presente
- il fallback locale per il dismiss resta solo come compatibilita' se il payload canonico manca

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift --format text`

## Esito
- il panel review smette di ricostruire inutilmente lo snapshot post-mutation quando il core Rust lo fornisce gia' canonico
- il boundary review strict resta senza nuove violazioni
