# P2 — Mutazioni snapshot offline del command bus ancora in Swift

## Sintomo
Quando una review session non era live nel registry, il command bus continuava a mutare in Swift lo snapshot persistito per `apply_fix`, `dismiss` e `comment`.

## Impatto
- Business logic duplicata tra planning Rust e fallback snapshot-side Swift.
- Drift semantico possibile tra percorso live e percorso persisted-only.
- Maggiore rischio di regressioni nel panel quando i comandi MCP agiscono su snapshot non live.

## Fix applicato
- aggiunto `review_core_command_mutate_snapshot` nel core Rust
- introdotto `review_command::mutator`
- collegato `ReviewCommandRustBridge` anche al path di mutazione snapshot
- mantenuto `close_finding` in Swift fuori scope per questa tranche

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`

## Residuo
`close_finding` e parte del patch runtime restano ancora nel bootstrap Swift. Questa tranche chiude solo le mutazioni snapshot offline più frequenti.
