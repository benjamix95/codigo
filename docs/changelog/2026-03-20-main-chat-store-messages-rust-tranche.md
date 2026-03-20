## 2026-03-20

- esteso il contratto shared [main_chat_store.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_store.rs) con `subagentCards`
- spezzata la logica Rust dei messaggi in moduli sotto [messages.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/store/messages.rs)
- aggiunte action Rust per:
  - insert before anchor
  - sync assistant content
  - sync assistant pipeline state
  - remove trailing empty assistant messages
  - save subagent cards to last assistant
  - remove assistant message if empty
- spostati i wrapper pubblici in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift)
- eliminato [ChatStoreMessages.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Messages/ChatStoreMessages.swift)
- eliminato [ChatStoreMessages+Pipeline.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Messages/ChatStoreMessages+Pipeline.swift)
- aggiunte regressioni in:
  - [ChatStoreStreamingTargetTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift)
  - [tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/store/tests.rs)
