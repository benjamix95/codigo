# 2026-03-21 chat store streaming assistant fallback fix

## Summary
- corretto il fallback XCTest di `ChatStore+RustBridge` per mutazioni assistant-centriche del turno streaming
- il fallback locale ora aggiorna contenuto assistant, `isStreaming` e rimozione dei trailing assistant vuoti quando Rust e' deferito

## Changes
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - aggiunto target assistant locale coerente con il path Rust
  - aggiunto fallback locale per `updateLastAssistantMessage`
  - aggiunto fallback locale per `setLastAssistantStreaming`
  - aggiunto fallback locale per `removeTrailingEmptyAssistantMessages`

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatPanelReasoningMergeTests -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests`
