# P1 - La riduzione eventi e stato della main chat era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: il path live della `main chat` continuava a ridurre `ChatPipelineEvent` in Swift tramite [ChatPipelineReducer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineReducer.swift), sia nel runtime [PipelineIntegrationService+ChatPipeline.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift) sia nel binding UI [ChatPanelView+PipelineChat.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift).
- Sintomo:
  - `PipelineIntegrationService` applicava ancora `ChatPipelineReducer.apply(...)` come source of truth
  - `ChatPanelView` ricostruiva ancora lo snapshot turno in Swift
  - il core Rust non aveva ancora contratti `main chat` né FFI dedicate
- Impatto: il cutover `main chat -> Rust only` restava bloccato sul path più sensibile della timeline chat, con rischio di regressioni duplicate fra reducer Swift e reducer futuro Rust.
- Gravita': alta, perche' tocca ownership del dominio e parità del comportamento osservabile della chat principale.
- Steps to reproduce:
  1. Aprire [PipelineIntegrationService+ChatPipeline.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift).
  2. Verificare la chiamata diretta a `ChatPipelineReducer.apply(...)`.
  3. Aprire [ChatPanelView+PipelineChat.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift) e osservare la stessa riduzione locale.
- Risultato attuale: il dominio chat rimaneva duplicato in Swift, senza un boundary Rust riusabile e testabile.
- Risultato atteso: la riduzione live della `main chat` deve poter passare attraverso un core Rust versionato, mantenendo un fallback Swift solo come compatibilità temporanea.
- Causa probabile: il cutover review aveva già introdotto `ReviewCoreBridge`, ma mancavano ancora contratti e FFI `main chat` equivalenti.
- Scope consentito:
  - [main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/main_chat.rs)
  - [ffi/main_chat.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/main_chat.rs)
  - [reducer.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/reducer.rs)
  - [runtime.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/runtime.rs)
  - [provider.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/provider.rs)
  - [ChatPipelineCommitter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineCommitter.swift)
  - [PipelineIntegrationService+ChatPipeline.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift)
  - [ChatPanelView+PipelineChat.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift)
  - [ChatPipelineReducerTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPipelineReducerTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - trasporto provider in Rust
  - persistenza completa `ChatStore`
  - direct stream runtime completo
  - plan multi-turn runtime completo
- Moduli confinanti da verificare:
  - `PipelineIntegrationServiceTests`
  - `ConversationFlowCoordinatorTests`
  - `rust_cutover_guard`
  - loader dylib review già esistente
- Test da aggiungere o aggiornare:
  - parity su [ChatPipelineReducerTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatPipelineReducerTests.swift)
  - unit test Rust per reducer/runtime/provider `main_chat`
- Strategia di fix minimo:
  - introdurre contratti shared `main chat` in `AppCoreProtocol`
  - aggiungere un dominio Rust `main_chat` con reducer/runtime/provider bridgeable via FFI
  - instradare il path live della riduzione chat attraverso Rust con fallback immediato al reducer Swift esistente
  - evitare nuovi file Swift non-UI fuori budget, concentrando il bridge dentro un file legacy già esistente
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/lib.rs,Native/AppCoreProtocol/src/main_chat.rs,Native/RustCore/Cargo.toml,Native/RustCore/src/lib.rs,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/ffi/main_chat.rs,Native/RustCore/src/main_chat/mod.rs,Native/RustCore/src/main_chat/reducer.rs,Native/RustCore/src/main_chat/runtime.rs,Native/RustCore/src/main_chat/provider.rs,App/SoloCodeApp/Sources/Chat/Pipeline/Core/ChatPipelineCommitter.swift,App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift,App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PipelineChat.swift,Tests/SoloCodeAppTests/ChatPipelineReducerTests.swift,scripts/validate_rust_cutover_boundary.sh,'Solo Code.xcodeproj/project.pbxproj' --format text`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests` attualmente bloccato da crash bootstrap del runner app-side
- Commit previsto: `feat(main-chat): add rust reducer bridge for live chat state`

## Effetto osservato
- Il path live della `main chat` puo' ora ridurre eventi e stato tramite FFI Rust.
- Il fallback Swift resta attivo, quindi il comportamento osservabile non dipende da un cutover atomico.
- Il dominio `main-chat` entra nel core Rust senza introdurre nuovi file Swift non-UI fuori policy.
