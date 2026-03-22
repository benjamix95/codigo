## 2026-03-21

## Modifiche
- aggiunto un nuovo contratto shared in [main_chat_provider.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_provider.rs) per risolvere il runtime transport della main chat lato Rust
- aggiunto il boundary FFI `chat_core_provider_resolve_transport` in [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
- introdotto il resolver Rust dedicato in [runtime_transport.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/runtime_transport.rs) per:
  - selezione `providerId` runtime
  - mappatura backend
  - policy read-only plan
  - sandbox Codex e `claudeAllowedTools`
- ridotta l'ownership Swift in [RustMainChatProviderFactory.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift) e [ChatPanelView+PartN_RuntimeTransportSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift):
  - Swift non decide piu' `providerId/backend/model/sandbox/tools`
  - il path main chat fallisce chiuso quando il boundary Rust non e' disponibile
- assorbito [ChatPanelView+PartI_TurnProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartI_TurnProvider.swift) dentro [ChatPanelView+PartI_RuntimeHelpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartI_RuntimeHelpers.swift) e rimosso dal progetto Xcode per ridurre di 1 il backlog legacy `Chat` richiesto dal tranche gate

## Test
- aggiunti unit test Rust in [runtime_transport.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/runtime_transport.rs) per:
  - plan read-only
  - code review execution backend
  - fallback al provider selezionato
- aggiunti test app-side in [RustMainChatProviderFactoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift) per:
  - risoluzione read-only dal boundary Rust
  - fail-closed con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Validazione
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml runtime_transport -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml resolves_codex_executable -- --nocapture`
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::cli::process::tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/ProviderFactoryRuntimeParityTests -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests -only-testing:SoloCodeAppTests/ChatStoreMarkerSanitizationTests`
  - `scripts/validate_rust_cutover_boundary.sh --workspace /Users/benjaminstoica/SoloCode --files 'App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift,App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift,App/SoloCodeApp/Sources/Settings/ProviderFactory/Config/ProviderFactoryConfig.swift,Native/RustCore/src/main_chat/providers/cli/codex.rs,Native/RustCore/src/main_chat/providers/session_tests.rs,Tests/SoloCodeAppTests/CLIMultiAccountProviderAdapterTests.swift,Tests/SoloCodeAppTests/ChatStoreMarkerSanitizationTests.swift,Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift,Tests/SoloCodeAppTests/ProviderFactoryRuntimeParityTests.swift,Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift,Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift' --format json`

## Rischio controllato
- nessun fallback legacy Swift reintrodotto nel path live della main chat
- nessuna modifica a stream loop, rewind o persistenza in questa tranche
