# 2026-03-11 — Review command offline mutations Rust tranche

## Scope
- mutazione snapshot persistito del command bus review
- copertura regressiva sui comandi `comment` e `dismiss`

## Modifiche
- esteso `Native/RustCore/src/review_command/` con `mutator.rs`
- aggiunto l'entrypoint FFI `review_core_command_mutate_snapshot`
- esteso `ReviewCommandRustBridge` per richiedere al core Rust findings/events mutati
- aggiornato `CodigoApp+CodeReviewCommandMutations.swift` per usare Rust su `apply_fix`, `dismiss` e `comment`
- aggiunti test Rust per `dismiss` e `comment`
- aggiunta regressione app-side per il comando `comment`

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`

## Note
`close_finding` resta volutamente in Swift in questa tranche per non trascinare anche la semantica patch/validation fuori scope.
