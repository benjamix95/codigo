# 2026-03-13 - Rust cutover plan tools

## Modifiche
- aggiunto `plan_state_handle_action` al crate `RustCore` con supporto a:
  - create
  - read latest/history
  - step update/upsert/batch update/reorder/dependency set
  - walkthrough
  - diff
  - request user input
- spostata nel core Rust la gestione append-only degli snapshot piano e il calcolo del diff
- aggiornati gli handler `CoderIDEMCPServerApp+IDEStatePlan*` per delegare al bridge Rust e mantenere in Swift solo validazione e marshaling argomenti

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml plan_state -- --nocapture`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`: verde

## Impatto
- il dominio `plan_state` non è più posseduto dagli handler Swift del MCP server legacy
- la semantica di history/diff del piano ora ha un unico owner Rust, coerente con la direzione del cutover totale
