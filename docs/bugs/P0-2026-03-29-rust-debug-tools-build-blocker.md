# P0 — `debug_tools.rs` troncato rompe il build del Rust MCP server

## Bug Fix Record
- Categoria: A - Critico
- Bug: `Native/CoderideMCPServerRust/src/debug_tools.rs` conteneva blocchi incompleti in `debug_mark`, `debug_clean` e `debug_instrument`: `format!()` senza stringa, rami `match` vuoti e pattern di cleanup mancanti.
- Sintomo: il phase script Xcode `Build Rust MCP Server` falliva durante `xcodebuild test` con errori Rust su `format!` e `match arms have incompatible types`.
- Impatto: il target app non riusciva a compilare il server MCP Rust; la validazione Xcode dell'intero progetto veniva interrotta prima dei test Swift.
- Gravità: P0
- Steps to reproduce:
  1. Eseguire `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS'`.
  2. Attendere il phase script `Build Rust MCP Server`.
  3. Verificare il fail su `Native/CoderideMCPServerRust/src/debug_tools.rs`.
- Risultato attuale: compile error Rust nel phase script Xcode e in `cargo test` del crate `coderide_mcp_server_rust`.
- Risultato atteso: il crate Rust MCP deve compilare e i test Xcode non devono più essere bloccati da `debug_tools.rs`.
- Causa probabile: copia locale/worktree di `debug_tools.rs` finita in stato troncato durante le validazioni, con rimozione delle stringhe dei `format!()` e del contenuto del `match` in più punti.
- Scope consentito: `Native/CoderideMCPServerRust/src/debug_tools.rs`, `Native/CoderideMCPServerRust/tests/catalog_contract.rs` per l'allineamento del count già modificato nello stesso intervento.
- Non-scope: refactor del dominio debug tools, redesign del formato dei marker, altri crate Rust.
- Moduli confinanti da verificare: phase script `scripts/build_rust_mcp_server.sh`, test crate Rust `catalog_contract` e `server_smoke`, validazione Xcode del target `Solo Code`.
- Test da aggiungere o aggiornare:
  - `cargo test` in `Native/CoderideMCPServerRust`
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:CoderEngineTests/...`
- Strategia di fix minimo: ripristinare la copia locale di `debug_tools.rs` alla versione corretta già presente nel repository, lasciando invariata la semantica dei marker/debug snippets.
- Verifica post-fix:
  1. `cargo test` in `Native/CoderideMCPServerRust` -> verde
  2. `xcodebuild test ... -scheme 'Solo Code' ...` -> verde sul set mirato
- Commit previsto: nessun diff persistente richiesto se il file viene riportato identico a `HEAD`; il bug va comunque registrato perché blocca la validazione locale.
