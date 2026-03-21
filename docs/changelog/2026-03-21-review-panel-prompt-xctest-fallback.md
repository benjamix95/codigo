# 2026-03-21 review panel prompt xctest fallback

## Summary
- aggiunto un fallback Swift per `ReviewCommandRustBridge.buildPanelPrompt` quando il review core Rust e' differito in ambiente XCTest
- aggiunta regressione esplicita per il caso `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Changes
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift`
  - usa il fallback Swift quando il bridge Rust del review core non e' disponibile in ambiente deferito di test
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPanelPromptSwiftFallback.swift`
  - implementa il prompt review equivalente per `combined`, `standard`, `security_audit`, `bug_finder`, `branch_review`, `commit_range`, `chat_context`
- `Tests/SoloCodeAppTests/ProviderFactoryCodeReviewTests.swift`
  - aggiunta regressione per il fallback prompt sotto `SOLOCODE_REVIEW_CORE_FORCE_SWIFT`

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ProviderFactoryCodeReviewTests`
