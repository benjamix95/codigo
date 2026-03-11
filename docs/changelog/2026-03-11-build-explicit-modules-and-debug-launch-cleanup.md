# 2026-03-11 — Build explicit modules and debug launch cleanup

## Cosa cambia

- Disabilitato `SWIFT_ENABLE_EXPLICIT_MODULES` in [Common.xcconfig](/Users/benjaminstoica/SoloCode/Config/xcconfigs/Common.xcconfig) per eliminare i warning SwiftPM/NIO del dependency scan nel build standard Xcode.
- Rimossi due warning locali del codice Swift:
  - `await` inutile in `CodeReviewSessionState`
  - risultato ignorato di `runPSQL(...)` in `PostgresPersistenceStore`

## Risultato

- La build standard di `Solo Code-Debug` non mostra più:
  - warning `NIOCore/NIOPosix is missing a dependency on ...`
  - warning `No 'async' operations occur within 'await' expression`
  - warning `Result of call to 'runPSQL(databaseName:sql:)' is unused`
- Il bundle `Solo Code.app` buildato resta coerente e lanciabile come app macOS.

## Verifica eseguita

- `xcodebuild -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' build`
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- test review/history già toccati in questa tranche
