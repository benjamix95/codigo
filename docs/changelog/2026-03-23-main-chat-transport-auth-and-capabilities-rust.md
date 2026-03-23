# 2026-03-23 — Main chat transport auth and capabilities moved to Rust

## Cosa cambia

- il contract `main_chat_provider` del runtime transport restituisce ora anche:
  - `isAuthenticated`
  - `nativeImageAttachment`
  - `nativeDocumentAttachment`
  - `nativeFileAttachment`
- il core Rust calcola questi valori a partire dal provider risolto, dallo stato di autenticazione del registry e dagli snapshot CLI passati dall'host;
- `resolveMainChatTransportProvider(...)` non ricompone più localmente `authenticated` e `attachmentCapabilities`, ma usa il risultato del core Rust;
- il core Rust del transport continua a non possedere keychain, env/path o object construction host-side: consuma solo input host-fed.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_provider.rs`
- `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`
- `Tests/SoloCodeAppTests/ThreadProviderSelectionServiceTests.swift`

## Ownership

- altra porzione del post-resolution shaping del transport main chat è ora Rust-owned;
- Swift resta owner della costruzione finale dell'oggetto provider e delle sorgenti host-side (registry, keychain, env/path, account snapshot collection);
- la tranche 4 non è ancora finita: restano parti di shaping/policy nel dominio `RuntimeProvider` e `CLIAccountSnapshots`.

## Verifica

- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ThreadProviderSelectionServiceTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 in avanzamento
- avanzamento complessivo: `75%`
