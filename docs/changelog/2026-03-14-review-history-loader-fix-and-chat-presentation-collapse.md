# 2026-03-14 — Review history loader fix and chat presentation collapse

## Modifiche
- corretto [CodeReviewPanelStore+History.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift) per usare `VerifiedFindingsQueryService.listHistoricalFindings(query:)`
- rimosso [ReviewPanelChatPresentationModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatPresentationModels.swift)
- consolidato `ReviewPanelMessagePresentation` in [ReviewPanelChatModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- il loader history del panel punta ora al query service storico corretto
- nessun cambiamento funzionale previsto per i modelli chat oltre alla riduzione del file residuale

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatPresentationModels.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsLoadsDeferredSnapshotFromLoader -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsReadsPersistedWorkspaceHistory`

## Note
- `ReviewPanelFindingsHistoryLiveBoardTests` resta fragile su un path diverso dal loader corretto in questa tranche; il bug e' stato registrato separatamente
