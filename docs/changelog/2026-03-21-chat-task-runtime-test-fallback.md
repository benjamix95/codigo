# 2026-03-21 chat task runtime test fallback

## Summary
- evitato il crash di `PipelineIntegrationServiceTests` quando il task runtime Rust e' deferito in ambiente XCTest
- introdotto un fallback locale del task runtime solo per i test, isomorfo al reducer Rust `main_chat/task_runtime.rs`

## Changes
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - nuovo fallback locale per `begin_task`, `end_task`, `set_task_status`
  - `applyRustTaskRuntimeAction` usa il fallback solo quando il bootstrap Rust e' deferito nei test

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests/testHandleTaskCompletedMarksCanonicalTodoDoneForReviewerAndTestWriter`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`
