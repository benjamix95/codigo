# 2026-03-21 chat store checkpoint test fallbacks

## Summary
- completati i fallback locali del `ChatStore` in ambiente test per `addMessage`, `createCheckpoint`, `rewindConversationState` e `persistPlanBoard`
- allineata la semantica locale ai reducer Rust dello store per evitare regressioni nei test app-side

## Changes
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `addMessage` usa fallback locale in XCTest
- `App/SoloCodeApp/Sources/Services/ChatStore/Checkpoints/ChatStoreCheckpoints.swift`
  - fallback locale per create/rewind checkpoint e rewind a message count
- `App/SoloCodeApp/Sources/Services/ChatStore/Plans/ChatStorePlans+SharedStateSync.swift`
  - `persistPlanBoard` usa fallback locale in XCTest

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreCheckpointTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests/testHandleTaskCompletedMarksCanonicalTodoDoneForReviewerAndTestWriter`
