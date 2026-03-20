# 2026-03-20 — Main Chat direct stream Rust-only tranche

## Modifiche
- esteso [main_chat_runtime.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_runtime.rs) con `eventKind` e `payload` per il consumo runtime degli eventi provider
- esteso il runtime Rust:
  - [runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/runtime.rs) ora gestisce l'action `direct_stream_apply_provider_event`
  - [stream_runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/stream_runtime.rs) applica in Rust il provider event al `turn_state`, aggiornando anche lo snapshot `direct_stream`
- aggiornato il wiring Swift:
  - [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift) e' ridotto a bridge FFI + wait helper generico
  - [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift) non usa piu' `MainChatRustBridge.reduce(...) ?? ChatPipelineReducer.apply(...)`
  - rimosso il fallback `runStreamLegacy(...)`; il path `direct stream` ora fallisce chiuso se Rust non e' disponibile
- aggiornati i test app-side in [ConversationFlowCoordinatorTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift) per:
  - risolvere esplicitamente la dylib Rust
  - verificare il fail-closed quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
- aggiornata la allowlist [rust-cutover-swift-allowlist.txt](/Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt) per riclassificare [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift) come `binding_adapter`
- aggiornata la allowlist [rust-cutover-swift-allowlist.txt](/Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt) per riclassificare anche [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift) come `binding_adapter`
- assorbito [DebugProjectionStoreBinding.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/DebugPipeline/DebugProjectionStoreBinding.swift) in [DebugProjectionEventConsumer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/DebugPipeline/DebugProjectionEventConsumer.swift), rimuovendo un file Swift dal prefisso `Runtime`
- aggiornata la baseline [RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md): il dominio `Runtime` scende da `13` a `10`, il totale canonico da `195` a `192`

## Risultato
- il direct stream della `main chat` e' ora Rust-only per:
  - consumo provider event
  - riduzione `turn_state`
  - terminalizzazione fail-closed
- il loop Swift resta solo adapter di attesa `AsyncSequence` e callback UI
- avanzamento strutturale canonico: `6 / 198 = 3.0%`
- avanzamento capability `main chat`: `85%`

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests`
  - build del target test completata
  - esecuzione test bloccata da crash pre-bootstrap del test runner app-hosted (`Early unexpected exit`)

## Note
- questa tranche non elimina ancora il wait helper `nextEvent(...)`, che resta infrastructure glue sul lato Swift
- il prossimo target consigliato per Rust puro resta il bootstrap config/watchdog helper residuo in `ConversationFlowCoordinator+Support.swift` e la restante ownership live in [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift)
