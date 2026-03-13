# 2026-03-13 - Rust cutover todo tools

## Modifiche
- aggiunto `todo_state_handle_action` al crate `RustCore`
- portati in Rust:
  - `todo_read`
  - `todo_write`
  - canonicalizzazione e merge dei todo legacy/explicit-id
  - rendering del testo restituito da `todo_read`
- aggiornato `CoderIDEMCPServerApp+IDEStateTools.swift` per delegare `todo_*` al bridge Rust
- mantenuto in Swift solo il parsing dei payload checklist/JSON tramite `IDEStateTodoArgumentParser`

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml todo_state -- --nocapture`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`: verde

## Impatto
- i tool `todo_*` non hanno più ownership Swift del persistence behavior
- il blocco IDE-state Swift si riduce ulteriormente a parser/adapter e piccoli ack UI-oriented
