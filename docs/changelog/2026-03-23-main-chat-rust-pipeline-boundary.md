# 2026-03-23 — Main chat Rust pipeline boundary

## Cosa cambia

- il boundary `main_chat_ui` accetta ora un `pipelineEvent` esplicito per applicare eventi live della chat nel core Rust;
- `PipelineIntegrationService` usa il boundary Rust come path standard per ridurre e sincronizzare lo stato chat live, senza fallback Swift implicito nel path normale;
- `PipelineLegacyChatAdapter` usa lo stesso boundary Rust per gli eventi pipeline legacy della chat;
- il merge locale del `ChatStore` non viene più forzato nel path standard degli intent stream/pipeline;
- la sincronizzazione Rust `runtime -> store snapshot` include ora anche il blocco `reasoning`, così i blocchi timeline restano coerenti col reducer di dominio.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_ui.rs`
- `Native/RustCore/src/main_chat/ui_intents.rs`
- `Native/RustCore/src/main_chat/ui_state_sync.rs`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatStoreBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+ChatPipeline.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters/PipelineLegacyChatAdapter.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift`
- test Rust/app-side del boundary `main_chat_ui`

## Note di ownership

- il reducer standard della pipeline live della chat passa ora dal core Rust via `pipeline_apply_event`;
- il fallback Swift resta consentito solo come path esplicito di test quando il bootstrap Rust è deferito in XCTest;
- i store host (`TodoStore`, `TaskActivityStore`, `SwarmProgressStore`, `DebugStore`) restano host-side in questa tranche.

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml pipeline_apply_event -- --nocapture`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml ffi_ui_handle_intent_pipeline_apply_event_updates_store_snapshot -- --exact`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
