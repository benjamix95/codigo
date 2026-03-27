# Fix: `solocode_rust_core` — `writeln!` su `File` senza `std::io::Write`

## Sintomo

`cargo build -p solocode_rust_core` falliva con:

`error[E0599]: cannot write into File` su `writeln!(f, ...)` in `codex_app_server.rs`.

## Causa

`writeln!` per `std::fs::File` usa il trait `std::io::Write`, che va importato nello scope (`use std::io::Write` o incluso nell’`use` aggregato di `std::io`).

## Risoluzione

Aggiunto `Write` all’import `std::io` in `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`.

## Verifica

`cargo build -p solocode_rust_core` (workspace `Native/`) completato con successo.
