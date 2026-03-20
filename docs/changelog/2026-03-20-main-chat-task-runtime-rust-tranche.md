## 2026-03-20

- aggiunto il contratto shared [main_chat_task_runtime.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_task_runtime.rs)
- aggiunto il runtime Rust [task_runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/task_runtime.rs)
- esposta la FFI `chat_core_task_runtime_handle_action` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- le entrypoint `beginTask`, `endTask`, `setTaskStatus` sono state assorbite in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift)
- rimosso il fallback Swift locale del task runtime: le mutazioni live del task ora sono Rust-owned e falliscono chiuse se il bridge non risponde
- eliminato [ChatStoreStreaming.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRuntime/ChatStoreStreaming.swift)
- aggiunta regressione in [ChatStoreTaskOwnershipTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreTaskOwnershipTests.swift) per verificare che `setTaskStatus` non crei task state mancante
- aggiunto test FFI Rust in [main_chat_task_runtime.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/main_chat_task_runtime.rs) per verificare il runtime task tramite `libsolocode_rust_core.dylib`
