# 2026-03-11 — Review command planning Rust tranche

## Scope
- command planning del code review bus
- wiring del bridge Rust nel target app
- regressione sul loop `dismiss`

## Modifiche
- aggiunto `Native/RustCore/src/review_command/` con modelli e planner Rust
- esteso `Native/RustCore/src/ffi.rs` con `review_core_command_plan`
- aggiornato `Native/RustCore/src/lib.rs` per registrare il modulo `review_command`
- introdotto `ReviewCommandRustBridge` lato app in `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/ReviewCommandRustBridge.swift`
- aggiornato `SoloCodeApp+CodeReviewCommands.swift` per usare il planner Rust prima del dispatch locale
- aggiunta copertura Rust su `dismiss` e `apply_patch`
- aggiunta regressione app-side su `dismiss` con stato finale `wont_fix`
- aggiornato il progetto Xcode per includere `ReviewCommandRustBridge.swift`

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`

## Note
Questa tranche chiude la validazione/normalizzazione dei comandi review nel core Rust, ma non sposta ancora tutta la mutazione snapshot offline o il patch executor runtime.
