# 2026-03-11 — Fix build locale: bridge patch Rust e build phase Xcode

## Modifiche
- reso accessibile `ReviewPatchRustBridge` al target app
- irrobustito il build phase Rust in Xcode:
  - check di leggibilità del crate
  - skip pulito quando il sandbox non permette accesso al crate
  - niente errore rumoroso su `Cargo.toml` nel path normale di build

## Validazione eseguita
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`

## Esito
- il build locale dell’app ora passa anche senza env speciali
- il backend Rust continua a poter essere costruito manualmente con `scripts/build_rust_search_backend.sh`
