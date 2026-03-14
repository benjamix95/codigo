# 2026-03-14 — Review panel settings model collapse

## Modifiche
- rimosso [ReviewPanelSettingsModel.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelSettingsModel.swift)
- spostati settings ed enum in [CodeReviewPanelModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift)
- spostati `ReviewPanelCustomCommand` e `ReviewPanelSettingsPersistence` in [ReviewPanelChatModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- i modelli del panel review sono meno frammentati e il custom command mantiene lo stesso contratto osservabile

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelSettingsModel.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`

## Note
- questa tranche riduce il debito Swift non-UI del panel review senza introdurre nuovi file
