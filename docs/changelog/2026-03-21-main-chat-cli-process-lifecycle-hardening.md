## 2026-03-21

## Modifiche
- aggiornato il runner CLI Rust in [process.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/process.rs) per leggere `stdout` su thread dedicato e verificare il cancel con polling non bloccante
- aggiunta raccolta parallela di `stderr` e propagazione del contenuto nei failure path `process_exit_*`
- mantenuta invariata la firma pubblica del runner e dei provider `codex`, `claude`, `gemini`, confinando il fix al layer process lifecycle

## Test
- aggiunti test Rust dedicati in [tests.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/process/tests.rs) per:
  - cancel di un processo silenzioso senza `stdout`
  - propagazione del `stderr` in uscita con codice non zero

## Validazione
- verde:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::cli::process::tests -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::session_tests -- --nocapture`
