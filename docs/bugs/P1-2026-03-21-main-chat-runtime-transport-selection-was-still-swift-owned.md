## Bug Fix Record
- Categoria: A
- Bug: la main chat continuava a risolvere `providerId`, backend runtime, modello e policy read-only del transport in Swift, con fallback al provider legacy quando il boundary Rust non rispondeva.
- Sintomo:
  - ownership divisa della selezione provider/runtime tra Swift e Rust
  - rischio di drift tra transport Rust, plan/code-review runtime e fallback legacy
- Impatto:
  - il path live della chat non era realmente Rust-only
  - possibile divergenza su `planModeBackend`, `codeReviewExecutionBackend`, sandbox Codex e tool list Claude
- Gravita': P1
- Steps to reproduce:
  1. selezionare un provider chat compatibile con Rust transport
  2. attivare plan inline o code review runtime
  3. osservare che Swift decide ancora `providerId/backend/model/sandbox/tools`
  4. forzare l'indisponibilita' del boundary Rust e verificare il fallback al provider legacy
- Risultato attuale:
  - la decisione runtime resta in `RustMainChatProviderFactory.swift`
  - il bridge puo' ricadere su `resolveRuntimeProvider(...)`
- Risultato atteso:
  - tutta la selezione del runtime transport deve essere risolta dal core Rust
  - il path main chat deve fallire chiuso quando il boundary Rust e' indisponibile
- Causa probabile:
  - il cutover della provider selection era rimasto a meta': `thread provider selection` in Rust, ma `runtime transport selection` ancora in Swift
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_provider.rs`
  - `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
  - `Native/RustCore/src/ffi/main_chat.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/**`
  - test Rust/App-side collegati
  - doc/changelog
- Non-scope:
  - stream loop
  - rewind/persistenza
  - login/account provisioning
- Moduli confinanti da verificare:
  - `ThreadProviderSelectionService`
  - `ChatPanelView+PartN_RuntimeTransportSelection.swift`
  - `RustMainChatProviderFactoryTests.swift`
- Test da aggiungere o aggiornare:
  - unit test Rust per il resolver runtime transport
  - test app-side che verifica plan read-only e fail-closed con Rust disabilitato
- Strategia di fix minimo:
  - aggiungere un boundary FFI dedicato `chat_core_provider_resolve_transport`
  - spostare in Rust la risoluzione di `providerId/backend/model/sandbox/tools`
  - lasciare in Swift solo display/auth/attachment lookup e costruzione finale della session config
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml runtime_transport -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests`
- Commit previsto:
  - `fix(chat): move runtime transport selection into rust`
