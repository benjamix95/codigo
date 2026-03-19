# 2026-03-19 — Review command lifecycle fail-closed

## Modifiche
- rimosso il fallback semantico Swift per le live mutation `apply_fix`, `dismiss` e `comment` in `ReviewSessionRegistry`
- resa fail-closed la finalizzazione deferred del `review_start` quando il runtime Rust non è disponibile
- aggiunta copertura di regressione engine per live mutation con review core disabilitato
- aggiunta copertura app-side per il caso in cui il runtime Rust diventi indisponibile dopo il launch del command deferred

## Motivazione
- chiudere la parte residua della tranche 3 in cui il lifecycle command-side poteva ancora riuscire senza ownership Rust reale

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewSessionRegistryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`
