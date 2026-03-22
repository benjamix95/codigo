## 2026-03-21

## Modifiche
- aggiunto un resolver Swift condiviso in [ProviderFactoryConfig.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Settings/ProviderFactory/Config/ProviderFactoryConfig.swift) per ottenere `codexPath` gia' risolto tramite `CodexDetector`
- aggiornato il bridge del transport Rust in [ChatPanelView+PartN_RuntimeTransportSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift) per inoltrare il path Codex risolto, non solo il valore raw configurato
- aggiunto fallback locale lato Rust in [codex.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex.rs) con precedence:
  - `CODEX_PATH` dell'account CLI
  - `config.codex_path`
  - auto-detect locale
- mantenuto invariato l'errore pubblico `missing_codex_path` quando nessuna sorgente produce un path valido

## Test
- aggiunti test Rust dedicati in [tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/codex/tests.rs) per precedenza e fallback del resolver
- aggiunti test app-side in [RustMainChatProviderFactoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift) per la risoluzione del `codexPath` destinato al transport Rust
- riallineato [session_tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/session_tests.rs) al nuovo comportamento con auto-detect

## Validazione
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml resolves_codex_executable -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml missing_codex_path -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml missing_cli_path_bubbles_error_into_session_events -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/ProviderFactoryRuntimeParityTests`
- verde sul diff della tranche:
  - `scripts/validate_rust_cutover_boundary.sh --workspace /Users/benjaminstoica/SoloCode --files 'App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift,App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift,App/SoloCodeApp/Sources/Settings/ProviderFactory/Config/ProviderFactoryConfig.swift,Native/RustCore/src/main_chat/providers/cli/codex.rs,Native/RustCore/src/main_chat/providers/session_tests.rs,Tests/SoloCodeAppTests/CLIMultiAccountProviderAdapterTests.swift,Tests/SoloCodeAppTests/ChatStoreMarkerSanitizationTests.swift,Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift,Tests/SoloCodeAppTests/ProviderFactoryRuntimeParityTests.swift,Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift,Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift' --format json`
- gate repo ancora rosso:
  - `scripts/solocode-validate --trigger gitCommit ...`
  - motivo: `Rust Cutover Boundary Audit` con `Nuove violazioni: 0`, ma budget legacy gia' sforato in `App/SoloCodeApp/Sources/Chat`

## Rischio controllato
- nessuna modifica alla proiezione UI degli errori
- nessuna reintroduzione di fallback comportamentali Swift nel runtime provider
- la tranche resta confinata alla risoluzione/config del provider `codex-cli`
