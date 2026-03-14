# 2026-03-14 — auto code review routing tests collapse

## Cosa cambia
- rimosso `AutoCodeReviewRoutingTests.swift`
- spostati i casi di auto-routing review in `ProviderFactoryCodeReviewTests.swift`
- rimosso il riferimento del file dal progetto Xcode

## Perché
- il file test dedicato era un residuo minimo della suite app-side review provider

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tests/SoloCodeAppTests/ProviderFactoryCodeReviewTests.swift,Tests/SoloCodeAppTests/AutoCodeReviewRoutingTests.swift,\"Solo Code.xcodeproj/project.pbxproj\" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests`
