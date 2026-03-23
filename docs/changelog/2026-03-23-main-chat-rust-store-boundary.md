# 2026-03-23 — Main chat Rust store boundary

## Cosa cambia

- il core store Rust normalizza ora gli snapshot caricati/sostituiti, ricostruendo `primaryText` e `reasoning` blocks quando i dati persistiti sono più poveri;
- `sync_assistant_pipeline_state` nel core Rust preserva il testo assistant già visibile quando il commit pipeline arriva senza contenuto ma con artifact/blocchi;
- il bridge Swift `ChatStore+RustBridge` usa fallback locali solo quando il bootstrap Rust è esplicitamente deferito in XCTest;
- il path standard non fa più merge euristico `Rust vs locale` in `RustMainChatStoreAdapter.apply(...)`;
- il bridge store non decide più “chi vince” tra snapshot Rust e stato locale nel caso standard.

## File toccati

- `Native/RustCore/src/main_chat/store/messages.rs`
- `Native/RustCore/src/main_chat/store/messages/helpers.rs`
- `Native/RustCore/src/main_chat/store/messages/assistant.rs`
- `Native/RustCore/src/main_chat/store/queries.rs`
- `Native/RustCore/src/main_chat/store/tests/messages.rs`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`
- `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`

## Ownership

- il path standard `store action -> snapshot -> apply` è ora Rust-first;
- il fallback Swift resta solo per `XCTest` con bootstrap Rust deferito;
- le euristiche host-side su preservazione contenuto e normalizzazione snapshot non sono più parte del path normale.

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml sync_assistant_pipeline_state_preserves_existing_visible_text_when_incoming_is_empty -- --nocapture`
- `cargo test --manifest-path Native/RustCore/Cargo.toml load_snapshot_normalizes_primary_text_and_reasoning_blocks -- --nocapture`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- avanzamento complessivo: `40%`
