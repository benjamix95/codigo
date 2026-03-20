# 2026-03-20 — Main chat provider transport tranche 3

## Summary
- aggiunto il contratto `main_chat_provider` nel protocollo condiviso
- introdotto un session runtime provider Rust con start/resume/get_snapshot/cancel via FFI
- aggiunti worker/provider Rust per `codex-cli`, `claude-cli`, `gemini-cli`, `openai-api`, `anthropic-api`, `google-api`
- instradato il path main chat su un transport provider Rust-backed senza toccare il layer UI

## Rust
- aggiornato [main_chat_provider.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat_provider.rs) con snapshot/config/eventi/session response per il transport provider
- esteso [Cargo.toml](/Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml) con dipendenze `reqwest` e `base64`
- aggiunto il dominio provider in [providers](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers)
- esteso [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs) con:
  - `chat_core_provider_start_session`
  - `chat_core_provider_resume`
  - `chat_core_provider_get_snapshot`
  - `chat_core_provider_cancel`
- mantenuto `chat_core_provider_stream` per la riduzione chunk legacy già presente

## Swift
- ripristinato [ChatPanelView+PartN_RuntimeProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartN_RuntimeProvider.swift) come selettore base/fallback, senza usarlo come source of truth del transport Rust
- implementato il bridge Swift provider session in:
  - [MainChatProviderBridgeModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift)
  - [RustMainChatProviderAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift)
  - [ChatPanelView+PartN_RuntimeTransportSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartN_RuntimeTransportSelection.swift)
- mantenuti piccoli shim file già presenti nel progetto per non aprire refactor inutili nel `pbxproj`

## Tests
- aggiunti test Rust sul parsing/router/session provider
- aggiunti test Swift in [RustMainChatProviderFactoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift)
- verifiche eseguite:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `cargo clippy --manifest-path Native/AppCoreRust/Cargo.toml --all-targets -- -D warnings`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/ProviderFactoryRuntimeParityTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
  - `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh --trigger manual --workspace /Users/benjaminstoica/SoloCode --files \"$(git diff --name-only --diff-filter=ACMR | paste -sd, -)\" --format text`

## Remaining blocker
- `cargo clippy --manifest-path Native/RustCore/Cargo.toml --all-targets -- -D warnings` fallisce ancora per lint preesistenti fuori scope della tranche provider; il dettaglio è documentato in [P2-2026-03-20-rustcore-clippy-all-targets-still-fails-on-preexisting-lints.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-20-rustcore-clippy-all-targets-still-fails-on-preexisting-lints.md)
