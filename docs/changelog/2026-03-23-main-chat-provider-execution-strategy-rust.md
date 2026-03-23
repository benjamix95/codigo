# 2026-03-23 — Main chat provider execution strategy moved to Rust

## Cosa cambia

- la decisione finale del ramo runtime provider della main chat non è più inferita in Swift da `fallbackAllowed` e `useSingleConfiguredProvider`;
- il core Rust del transport restituisce ora una strategia esplicita:
  - `selected_provider`
  - `multi_account_router`
  - `single_configured_provider`
  - `fail_closed`
- `ChatPanelView+PartN_RuntimeProvider.swift` applica soltanto quella strategia:
  - provider già selezionato
  - adapter multi-account
  - fallback al provider singolo configurato
  - chiusura del flusso con `nil`
- il boundary app-side mantiene solo la costruzione concreta del provider e l’emissione dell’eventuale hint utente.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_provider.rs`
- `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`

## Ownership

- il core Rust decide ora anche la strategia esecutiva del transport runtime per la main chat;
- Swift non sceglie più localmente se usare il router multi-account o degradare al provider singolo;
- l’ownership host-side residua resta limitata a secret storage, env overrides, router/accounts store e costruzione dell’istanza provider concreta.

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml runtime_transport -- --nocapture`
- `cargo test --manifest-path Native/AppCoreProtocol/Cargo.toml --quiet`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 quasi chiusa
- avanzamento complessivo: `96%`
