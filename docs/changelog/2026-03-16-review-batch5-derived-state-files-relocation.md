# 2026-03-16 - Review batch 5 derived state files relocation

## Batch completato
- ricollocati sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/`:
  - `CodeReviewPanelStore+PipelineJobState.swift`
  - `CodeReviewPanelStore+ProviderSelection.swift`
  - `CodeReviewPanelStore+Settings.swift`
  - `CodeReviewPanelStore+Summary.swift`
  - `CodeReviewPanelStore+History.swift`

## Verifica eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelDefaultsToFindingsTabAndUnifiedModes -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelProviderDefaultsToSelectedAgentProviderAndCanOverride -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoricalResumePromptIncludesPersistedLifecycleContext -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoryRefreshKeyStaysStableAcrossSnapshotTimestampUpdates -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`
- audit strict review-scope:
  - prima: `59` legacy non-UI
  - dopo: `54` legacy non-UI

## Note
- il prefisso panel-side scende da `9` a `4`
- il test `testPatchFinalizationTargetsUseRustReducer` non e' stato usato come gate di questo batch perche' dipende da un reducer Rust di finalizzazione patch non toccato in questa tranche
