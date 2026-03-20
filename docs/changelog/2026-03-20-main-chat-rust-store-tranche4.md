# 2026-03-20 — Main Chat Rust Store Tranche 4

## Summary
- La `main chat` usa ora un bridge store Rust-backed per snapshot, mutazioni chiave, checkpoint e rewind.
- Swift resta projection/UI + adapter `UserDefaults` e Git restore executor.

## Implementato
- nuovo contratto shared store in `Native/AppCoreProtocol/src/main_chat_store.rs`
- nuovo dominio Rust store/persistence sotto `Native/RustCore/src/main_chat/store` e `.../persistence`
- nuove FFI:
  - `chat_core_store_load`
  - `chat_core_store_replace_snapshot`
  - `chat_core_store_handle_action`
- nuovo bridge Swift store:
  - `MainChatStoreBridgeModels`
  - `RustMainChatStoreAdapter`
  - `ChatStore+RustBridge`
- mutazioni live reindirizzate su Rust per:
  - create/delete/update conversation core
  - append/update/remove message core
  - set streaming state
  - save reasoning
  - set plan board
  - create checkpoint
  - rewind a checkpoint
  - rewind a message count
  - load normalization store snapshot
- `ChatStoreStreaming.swift` spostato fuori dal prefisso `Chat/Store` per rispettare il budget strutturale del guard
- nuovo test Rust store reducer e mantenimento dei golden XCTest store/checkpoint/plan

## Verifiche
- `cargo test --manifest-path Native/RustCore/Cargo.toml`: verde
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`: verde
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreMigrationTests -only-testing:SoloCodeAppTests/ChatStoreCheckpointTests -only-testing:SoloCodeAppTests/ChatStorePlanAttachmentTests -only-testing:SoloCodeAppTests/ChatStorePlansMutationTests -only-testing:SoloCodeAppTests/ChatStoreAsyncHydrationTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`: verde
- `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh --files ...`: verde sul diff della tranche

## Progress
- `Capability: 80%`
- baseline strutturale `v3`: `132`
- residuo strutturale corrente `v3`: `131`
- `Strutturale v3: 0.8%`

## Note
- Il blocco store/persistence è ora Rust-backed per i path live principali, ma il drenaggio strutturale completo del dominio `store + pipeline engine` richiede ancora la tranche finale di rimozione legacy Swift.
- `cargo clippy --manifest-path Native/RustCore/Cargo.toml --all-targets -- -D warnings` resta bloccato da lint preesistenti multi-dominio già documentati nel bug P2 della tranche precedente.
