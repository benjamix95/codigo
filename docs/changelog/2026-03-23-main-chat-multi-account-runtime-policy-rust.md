# 2026-03-23 — Main chat multi-account runtime policy moved to Rust

## Cosa cambia

- la decisione `multi-account exhausted -> fallback al provider singolo / hard fail` della main chat non è più presa direttamente nel binding Swift;
- Swift passa al core Rust:
  - `multiCliAccountEnabled`
  - `providerAvailabilityStatus`
  - `providerAvailabilityReason`
  - `baseAuthenticated`
  - snapshot account CLI già normalizzati
- il core Rust del transport restituisce ora:
  - `fallbackAllowed`
  - `useSingleConfiguredProvider`
  - `failureReason`
  - `userFacingHint`
- `resolveRuntimeProvider(...)` applica semplicemente l’esito del core Rust nel ramo `multiCLIAccountEnabled`.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_provider.rs`
- `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`

## Ownership

- il core Rust decide ora anche il comportamento runtime della main chat quando il router multi-account segnala `allExhausted`;
- Swift resta owner del router/account store, delle env overrides e della costruzione concreta del provider;
- questa slice chiude un'altra ownership ibrida nel dominio `RuntimeProvider` senza toccare il provider stack generico condiviso.

## Verifica

- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 quasi chiusa
- avanzamento complessivo: `85%`
