## 2026-03-20

- aggiunto il contratto shared [main_chat_markers.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_markers.rs)
- aggiunto il runtime Rust markers sotto [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/markers/mod.rs)
- esposta la FFI `chat_core_markers_handle` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- spostate le facciate pubbliche markers in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift)
- eliminati:
  - [ChatStoreMarkers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Messages/ChatStoreMarkers.swift)
  - [ChatStoreMarkers+OperationalThinking.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Messages/ChatStoreMarkers+OperationalThinking.swift)
- aggiunte regressioni in:
  - [ChatStoreMarkerSanitizationTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreMarkerSanitizationTests.swift)
  - [main_chat_markers.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/main_chat_markers.rs)
