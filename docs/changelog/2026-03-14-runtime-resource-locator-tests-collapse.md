# 2026-03-14 — Runtime resource locator tests collapse

## Modifiche
- eliminato `Tests/SoloCodeAppTests/RuntimeResourceLocatorTests.swift`
- consolidato `RuntimeResourceLocatorTests` in `Tests/SoloCodeAppTests/ProviderFactoryCodeReviewTests.swift`
- aggiornato `Solo Code.xcodeproj/project.pbxproj`

## Validazione
- `./scripts/validate_rust_cutover_boundary.sh ...`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests -only-testing:SoloCodeAppTests/RuntimeResourceLocatorTests`
