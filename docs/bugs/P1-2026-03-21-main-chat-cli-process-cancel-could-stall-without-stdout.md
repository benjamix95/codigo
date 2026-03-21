## Bug Fix Record
- Categoria: A
- Bug: il runner CLI Rust della `main chat` poteva restare appeso in cancel se il processo figlio non produceva `stdout`, e i failure path perdevano il contenuto utile di `stderr`.
- Sintomo:
  - `cancel_session` marcava la sessione come cancellata ma il worker poteva restare bloccato in lettura su `stdout`
  - i process exit error restituivano solo `process_exit_<code>` senza dettaglio operativo dal `stderr`
- Impatto:
  - cancellazione non deterministica dei provider CLI in presenza di processi silenziosi
  - diagnosi difficile dei failure path del transport Rust
- Gravita': P1
- Steps to reproduce:
  1. avviare `stream_process_lines` con un comando che non emette `stdout`, ad esempio `sleep 5`
  2. alzare il flag di cancel prima che il processo scriva output
  3. osservare che il loop puo' attendere la fine naturale del processo invece di terminare subito
  4. in un secondo caso, eseguire un comando che scrive solo su `stderr` e termina con exit code non zero
  5. osservare che l'errore pubblico non include il contesto `stderr`
- Risultato attuale:
  - cancel dipendente dall'arrivo di una nuova linea su `stdout`
  - `stderr` ignorato nei failure path
- Risultato atteso:
  - cancel tempestivo anche quando il processo e' silenzioso su `stdout`
  - errori di uscita arricchiti con il `stderr` disponibile
- Causa probabile:
  - il runner leggeva `stdout` in modo bloccante nel thread principale e verificava il cancel solo tra una linea e l'altra, senza un canale concorrente o polling periodico
- Scope consentito:
  - [process.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/process.rs)
  - test Rust dedicati del runner CLI
  - doc bug/changelog
- Non-scope:
  - protocollo eventi provider
  - retry/failover policy dei provider CLI
  - orchestrazione Swift del direct stream
- Moduli confinanti da verificare:
  - `session_tests`
  - `codex.rs`
  - `claude.rs`
  - `gemini.rs`
- Test da aggiungere o aggiornare:
  - test Rust che riproduce il cancel di un processo silenzioso
  - test Rust che verifica la propagazione del `stderr` in exit error non zero
- Strategia di fix minimo:
  - mantenere invariata la firma pubblica del runner
  - leggere `stdout` su thread dedicato con polling del canale
  - raccogliere `stderr` in parallelo e allegarlo ai failure path
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::cli::process::tests -- --nocapture`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::providers::session_tests -- --nocapture`
- Commit previsto:
  - `fix(chat): harden rust cli process cancel and stderr propagation`
