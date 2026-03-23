## 2026-03-23 - Main chat runtime provider fail-closed

- Il path standard della main chat non torna piu' automaticamente al provider Swift locale quando il transport Rust non risolve il backend.
- Il fallback legacy del provider ora e' consentito solo in due casi:
  - XCTest esplicito
  - flag diagnostici `SOLOCODE_REVIEW_CORE_FORCE_SWIFT` / `SOLOCODE_REVIEW_CORE_DISABLE_RUST`
- Lo stesso gate piu' stretto viene applicato anche al provider read-only plan, cosi' il plan mode standard non ricostruisce piu' un provider locale Swift quando la risoluzione Rust manca.
- Aggiunte regressioni in `RustMainChatProviderFactoryTests` per verificare che il fallback legacy sia negato nel path standard e ammesso solo quando il defer Rust e' esplicito.

### Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests`

### Avanzamento
- Avanzamento complessivo del cutover Rust-first: **90%**

### Note
- Restano fuori da questa tranche i fallback test-only di `ChatStore+RustBridge` e il drenaggio completo dei rami locali del `UnifiedToolRuntime` per i tool gia' Rust-first.
