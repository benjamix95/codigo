# 2026-03-21 chat store test mode local fallbacks

## Summary
- corrette due mutazioni `ChatStore` che in ambiente test continuavano a dipendere dal bridge Rust anche quando il bootstrap Rust era deferito

## Changes
- `App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Conversations/ChatStoreConversations.swift`
  - `deleteConversation` usa fallback locale in XCTest
- `App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Plans/ChatStorePlans+SharedStateSync.swift`
  - `persistPlanBoard` aggiorna `planBoards` localmente in XCTest

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests/testHandleTaskCompletedMarksCanonicalTodoDoneForReviewerAndTestWriter`
