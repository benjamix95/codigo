# P1 - Il routing multi-account CLI viveva ancora in Swift

## Bug Fix Record
- Categoria: A
- Bug: la logica di routing account/provider per `codex`, `claude` e `gemini` viveva ancora in Swift dentro `CLIAccountRouter` e `CLIMultiAccountProviderAdapter`.
- Sintomo:
  - selection round-robin e active account in Swift
  - failover dopo errori quota/rate-limit in Swift
  - bootstrap active selections in Swift
  - availability degli account determinata in Swift
- Impatto: il cutover totale a Rust restava incompleto su uno dei backbone del prodotto; il path provider continuava a dipendere da semantica Swift di dominio, non solo da UI shell.
- Gravita': alta
- Steps to reproduce:
  1. Aprire [CLIAccountRouter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/Support/CLIAccountRouter.swift) e [CLIMultiAccountProviderAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/Support/CLIMultiAccountProviderAdapter.swift).
  2. Cercare `selectedOrNextAvailableAccount`, `markUsage`, `markProviderError`, `bootstrapActiveSelectionsIfNeeded`.
  3. Verificare che il comportamento business fosse ancora owned da Swift.
- Risultato attuale: la politica account/provider non era ancora Rust-owned.
- Risultato atteso: Swift prepara snapshot e applica risposta; selezione, disponibilita', cooldown, quota e failover sono owned da Rust.
- Causa probabile: il repo aveva gia' provider sessions Rust-backed per `main chat`, ma non ancora un runtime Rust dedicato al routing multi-account applicativo.
- Scope consentito:
  - `Native/AppCoreProtocol/src/cli_account_routing.rs`
  - `Native/RustCore/src/cli_account_routing/**`
  - `Native/RustCore/src/ffi/cli_account_routing.rs`
  - `Native/AppCoreRust/tests/app_core_boundary_accounts.rs`
  - `App/SoloCodeApp/Sources/Accounts/Support/CLIAccountRouter.swift`
  - `App/SoloCodeApp/Sources/Accounts/Support/CLIMultiAccountProviderAdapter.swift`
  - `App/SoloCodeApp/Sources/Accounts/Authentication/CLIAccountAuthDetector.swift`
  - `App/SoloCodeApp/Sources/Accounts/CLIAccountLoginSheet.swift`
  - `Config/validation/rust-cutover-swift-allowlist.txt`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - migrazione completa a Rust di detection auth via processo/CLI/file parsing
  - provisioning profili
  - UI settings/profile switcher
- Moduli confinanti da verificare:
  - `CLIAccountAuthDetectorTests`
  - `CLIMultiAccountProviderAdapterTests`
  - `xcodebuild build` app-side
  - `cargo test` di `RustCore`
- Test da aggiungere o aggiornare:
  - test Rust di bootstrap/selection/current active
  - test Rust di `mark_usage`
  - test Rust di `mark_provider_error` e `next_available_account_after`
  - test app-side di `hasAuthenticatedAvailableAccount`
  - test app-side su environment credential per provider
- Strategia di fix minimo:
  - introdurre contratto shared `cli_account_routing`
  - aggiungere FFI `cli_accounts_handle_action`
  - convertire `CLIAccountRouter` in bridge state/apply adapter
  - convertire `CLIMultiAccountProviderAdapter` a consumer del router Rust
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/solocode-mainchat-dd -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests`
- Commit previsto: `refactor(accounts): move cli account routing into rust`

## Effetto osservato
- il routing multi-account non dipende piu' da business logic Swift
- Swift resta wrapper di snapshot/auth/env glue; in questa tranche `CLIAccountAuthDetector.swift` e `CLIAccountLoginSheet.swift` sono stati compattati per eliminare helper Swift sparsi, non per reintrodurre ownership di dominio
- la fondazione `providers/accounts` del cutover totale avanza senza introdurre nuovo codice di dominio in Swift
