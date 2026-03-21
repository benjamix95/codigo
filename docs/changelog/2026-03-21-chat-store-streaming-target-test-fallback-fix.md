# 2026-03-21 chat store streaming target test fallback fix

## Summary
- corretto il fallback XCTest di `ChatStore+RustBridge` per mantenere il titolo della conversazione al primo messaggio utente
- aggiunto il fallback locale per `insertMessage(before:)` quando il core Rust e' deferito

## Changes
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - il fallback `addMessage` aggiorna il titolo se la conversazione e' ancora `New conversation`
  - `insertMessage(before:)` applica l'inserimento localmente in ambiente XCTest

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests/testAddMessageUpdatesNewConversationTitleFromFirstUserMessage -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests/testInsertMessagePlacesEntryBeforeAnchorMessage`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatPanelReasoningMergeTests -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests`
