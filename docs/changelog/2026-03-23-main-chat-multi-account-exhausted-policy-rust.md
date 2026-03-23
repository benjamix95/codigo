# 2026-03-23 — Main chat multi-account exhausted policy moved to Rust

## Cosa cambia

- il caso `CLI multi-account exhausted` della main chat non viene più deciso localmente nel binding Swift;
- Swift passa al core Rust del transport:
  - `multiCliAccountEnabled`
  - `providerAvailabilityStatus`
  - `providerAvailabilityReason`
  - `baseAuthenticated`
  - snapshot account CLI già normalizzati
- il core Rust restituisce:
  - `fallbackAllowed`
  - `useSingleConfiguredProvider`
  - `failureReason`
  - `userFacingHint`
- `resolveRuntimeProvider(...)` applica ora l’esito Rust per scegliere `fallback to single configured provider` oppure `fail closed`.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_provider.rs`
- `Native/RustCore/src/main_chat/providers/runtime_transport.rs`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`

## Ownership

- la main chat non possiede più lato Swift la policy finale di degradazione quando il router CLI segnala `allExhausted`;
- Swift resta owner del router/account store e della costruzione concreta del provider;
- questa slice chiude un’altra ownership ibrida del dominio `RuntimeProvider`.

## Verifica

- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 quasi chiusa
- avanzamento complessivo: `90%`
