# 2026-03-20 — Fondazione Rust del reducer `main chat`

## Modifiche
- introdotto il nuovo contratto shared [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat.rs) con schema versionato per:
  - stato turno chat
  - eventi chat normalizzati
  - richieste runtime `start/reduce/finish/action`
  - batch provider `provider_stream`
- esteso [RustCore/Cargo.toml](/Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml) per consumare `app_core_protocol` dal core Rust.
- aggiunto il nuovo dominio Rust `main_chat`:
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/mod.rs)
  - [artifacts.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/artifacts.rs)
  - [reducer.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/reducer.rs)
  - [runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/runtime.rs)
  - [provider.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/provider.rs)
- esposte le nuove entrypoint FFI:
  - [ffi/main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
  - registrazione in [ffi/mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/mod.rs)
- integrato il reducer Rust nel path live della chat, con fallback immediato al reducer Swift:
  - [ChatPipelineCommitter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineCommitter.swift)
  - [PipelineIntegrationService+ChatPipeline.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift)
  - [ChatPanelView+PipelineChat.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift)
- estesa la parity suite app-side in [ChatPipelineReducerTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPipelineReducerTests.swift).
- aggiornato [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh):
  - introdotti i prefissi `main-chat`
  - attivazione resa opt-in via `SOLOCODE_MAIN_CHAT_CUTOVER=1`
  - nessun impatto sul flusso review di default

## Motivazione
- iniziare il drenaggio reale della logica non-UI della `main chat` verso Rust senza introdurre un cutover atomico ad alto rischio.
- mantenere compatibilita' runtime con fallback Swift finche' la parita' non e' completa.
- evitare nuove violazioni del boundary Rust creando il bridge dentro file Swift legacy gia' esistenti.

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/lib.rs,Native/AppCoreProtocol/src/main_chat.rs,Native/RustCore/Cargo.toml,Native/RustCore/src/lib.rs,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/main_chat.rs,Native/RustCore/src/main_chat/mod.rs,Native/RustCore/src/main_chat/reducer.rs,Native/RustCore/src/main_chat/runtime.rs,Native/RustCore/src/main_chat/provider.rs,App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineCommitter.swift,App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift,Tests/SoloCodeAppTests/ChatPipelineReducerTests.swift,scripts/validate_rust_cutover_boundary.sh,'Solo Code.xcodeproj/project.pbxproj' --format text`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
  - build completata
  - esecuzione test bloccata da crash bootstrap del runner app-side (`Early unexpected exit`)
- `xcodebuild build -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - build completa con `** BUILD SUCCEEDED **`
- `cargo clippy --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml --all-targets -- -D warnings`
  - ancora bloccato da warning/lint preesistenti e non confinati nei moduli toccati
