# 2026-03-14 — review pipeline no-files message tests collapse

## Cosa cambia
- rimosso `ReviewPipelineNoFilesMessageTests.swift`
- spostati i test no-files in `CodeReviewPanelLiveRunExecutionTests.swift`
- mantenuta una classe `ReviewPipelineNoFilesMessageTests` separata nel file di destinazione
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo del sottodominio review panel execution

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift,Tests/SoloCodeAppTests/ReviewPipelineNoFilesMessageTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPipelineNoFilesMessageTests`
