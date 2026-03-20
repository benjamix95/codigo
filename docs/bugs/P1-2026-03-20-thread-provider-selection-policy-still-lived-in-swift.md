# P1 - La policy di selezione provider del thread viveva ancora in Swift

## Bug Fix Record
- Categoria: A
- Bug: la policy che decide `effectiveMode`, provider risolto e bound-provider mancante del thread `main chat` viveva ancora in Swift dentro `ThreadProviderSelectionService`.
- Sintomo:
  - `resolveProviderId` conteneva fallback `IDE`/`Agent`/`MCP Server` in Swift
  - `missingBoundProviderId` validava binding provider lato Swift
  - il path thread/provider restava fuori dal cutover Rust del `main chat`
- Impatto: il prodotto continuava a dipendere da semantica Swift in un nodo di orchestrazione centrale del `main chat`, con rischio di drift rispetto al runtime/provider path Rust.
- Gravita': alta
- Steps to reproduce:
  1. Aprire [ThreadProviderSelectionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Providers/Services/ThreadProviderSelectionService.swift).
  2. Verificare che `resolveProviderId`, `missingBoundProviderId` e la normalizzazione mode/provider fossero implementati localmente.
  3. Confrontare il path con il resto del runtime `main chat` gia' Rust-backed.
- Risultato attuale: la selection policy del thread non era ancora Rust-owned.
- Risultato atteso: Swift invia snapshot minimi del registry e riceve da Rust `effectiveMode`, provider risolto e bound-provider mancante.
- Causa probabile: il cutover si era fermato su runtime/store/provider transport, lasciando ancora in Swift la policy di thread binding.
- Scope consentito:
  - `Native/AppCoreProtocol/src/thread_provider_selection.rs`
  - `Native/RustCore/src/main_chat/providers/thread_selection.rs`
  - `Native/RustCore/src/ffi/main_chat.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
  - `Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift`
  - `Native/AppCoreRust/tests/app_core_boundary_main_chat.rs`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - transport provider runtime
  - provider session lifecycle
  - `persistRuntimeProviderSelection`, che resta mutazione Swift del `ChatStore`
- Moduli confinanti da verificare:
  - `ContentView+ProviderSelection`
  - `ChatPanelView+PartI_RuntimeHelpers`
  - `ChatPanelView+PartL_SendMessage`
  - `RustMainChatProviderFactory`
- Test da aggiungere o aggiornare:
  - unit test Rust sulla selection policy
  - XCTest su `ThreadProviderSelectionServiceTests`
  - boundary regression per allowlist del bridge Swift
- Strategia di fix minimo:
  - introdurre contratto shared `thread_provider_selection`
  - implementare policy Rust dedicata nel dominio `main_chat/providers`
  - esporre funzione FFI `chat_core_thread_provider_selection`
  - assorbire `ThreadProviderSelectionService` in un file Swift gia' allowlisted sotto `Providers/Rust/**`, eliminando un file Swift legacy dal prefisso `Chat`
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/solocode-thread-provider-dd -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests`
- Commit previsto: `refactor(chat): move thread provider selection policy into rust`
