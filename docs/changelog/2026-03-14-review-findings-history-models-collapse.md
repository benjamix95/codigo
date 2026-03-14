# 2026-03-14 — review findings history models collapse

## Cosa cambia
- rimosso `ReviewPanelFindingsHistoryModels.swift`
- spostati in `ReviewPanelFindingsHistoryTab.swift`:
  - `ReviewFindingHistoryStatusFilter`
  - `ReviewFindingHistoryDomainFilter`
  - `ReviewFindingHistorySeverityFilter`
- spostati in `ReviewPanelHistoricalFindingDetail.swift`:
  - helper derivati di `HistoricalFindingRecord`
- spostati in `ReviewPanelHistoricalLiveBoard.swift`:
  - `ReviewHistoricalLiveWorkerState`
  - `ReviewHistoricalLiveFileState`
  - `ReviewHistoricalLiveBoardState`
- aggiunta regressione sui derivati history in `ReviewPanelFindingsHistoryTests`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file history models era rimasto come frammento Swift legacy senza un boundary separato reale

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelFindingsHistoryTab.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelHistoricalFindingDetail.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelHistoricalLiveBoard.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelFindingsHistoryModels.swift,Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoricalFindingDerivedLabelsReflectLifecycleState -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoricalResumePromptIncludesPersistedLifecycleContext -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testResumeQueuePrioritizesOpenHistoricalFindings`
