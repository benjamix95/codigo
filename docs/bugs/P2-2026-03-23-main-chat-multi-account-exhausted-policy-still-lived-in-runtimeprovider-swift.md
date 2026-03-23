# Bug Fix Record
- Categoria: B
- Bug: nel dominio main chat la policy `multi-account exhausted -> fallback al provider singolo / hard fail` viveva ancora nel binding Swift `RuntimeProvider`.
- Sintomo: `ChatPanelView+PartN_RuntimeProvider.swift` decideva direttamente quando:
  - mostrare l’hint utente
  - degradare al provider singolo configurato
  - fallire chiuso restituendo `nil`
  in base a `CLIAccountRouter.currentAvailability(...)` e `selectedProvider.isAuthenticated()`.
- Impatto: il core Rust del transport risolveva già il provider e altra policy runtime, ma Swift manteneva ancora l’ownership finale del comportamento multi-account quando gli account CLI erano esauriti.
- Gravità: media
- Steps to reproduce:
  1. Attivare `multiCLIAccountEnabled`.
  2. Forzare `CLIAccountRouter.currentAvailability(provider:)` a `.allExhausted(...)`.
  3. Osservare che il binding Swift decide fallback o hard fail senza un esito esplicito del core Rust.
- Risultato attuale: la degradazione runtime del caso `allExhausted` era ancora host-owned.
- Risultato atteso: il core Rust del transport deve restituire un esito esplicito (`fallbackAllowed`, `useSingleConfiguredProvider`, `failureReason`, `userFacingHint`) e Swift deve solo applicarlo.
- Causa probabile: il cutover del transport provider si era fermato a `providerId/backend/auth/capabilities`, lasciando il caso multi-account exhausted nel binding host-side.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_provider.rs`
  - `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
  - `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`
- Non-scope:
  - router/account store host-side
  - env overrides, keychain, provider object construction
  - `ToolEnabledLLMProvider`
  - provider stack generico condiviso
- Moduli confinanti da verificare:
  - `RustMainChatProviderFactoryTests`
  - `CLIMultiAccountProviderAdapterTests`
- Test da aggiungere o aggiornare:
  - regression su `fallback to single configured provider`
  - regression su `fail closed when base provider is logged out`
- Strategia di fix minimo:
  - estendere il contract del transport con stato multi-account e hint/failure espliciti
  - far decidere al core Rust il caso `allExhausted`
  - usare l’esito Rust nel binding Swift senza mantenere policy locale
- Verifica post-fix:
  - `cargo build --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests`
- Commit previsto: `refactor(chat): move multi-account exhausted runtime policy into rust`
