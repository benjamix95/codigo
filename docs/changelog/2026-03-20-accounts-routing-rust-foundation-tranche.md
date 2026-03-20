# 2026-03-20 — Fondazione Rust del routing multi-account

## Modifiche
- aggiunto il contratto shared [cli_account_routing.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreProtocol/src/cli_account_routing.rs)
- aggiunto il nuovo dominio Rust:
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/cli_account_routing/mod.rs)
  - [availability.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/cli_account_routing/availability.rs)
  - [actions.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/cli_account_routing/actions.rs)
  - [tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/cli_account_routing/tests.rs)
  - [ffi/cli_account_routing.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/cli_account_routing.rs)
- `CLIAccountRouter` ora prepara snapshot e applica stato/aggiornamenti restituiti da Rust
- `CLIMultiAccountProviderAdapter` usa il router Rust per disponibilita' e failover
- `CLIAccountAuthDetector.swift` incorpora gli helper locali e copre il path `environment credential` per i tre provider senza creare nuovi file Swift
- `CLIAccountLoginSheet.swift` assorbe i partial UI rimossi, lasciando le sezioni come UI allowlisted e non business logic

## Risultato
- passano a Rust:
  - availability degli account
  - selection round-robin
  - selected-or-next-available
  - failover al prossimo account
  - mark usage / exhaustion policy
  - mark provider error / cooldown policy
  - bootstrap active selections
- restano in Swift, per ora:
  - auth detection via processo/file/env
  - provisioning profili
  - UI/settings/profile switcher

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/solocode-mainchat-dd -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/CLIAccountAuthDetectorTests`

## Progress
- `% capability totale`: `~7%`
- `% capability providers/accounts`: `~28%`
- `% strutturale totale`: `~1.1%` (`15 / 1310` sulla baseline workspace 2026-03-20)
- `% strutturale providers/accounts`: migliorato via allowlist canonica e rimozione helper Swift non-UI isolati

## Note
- questa tranche sposta ownership di dominio, non ancora il conteggio strutturale dei file `Accounts/Support/**`, che sono gia' allowlisted come adapter
- il prossimo passo naturale e' spostare in Rust anche la detection auth/identity e la policy di provisioning
