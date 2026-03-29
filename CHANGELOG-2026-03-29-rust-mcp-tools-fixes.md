# Changelog - 2026-03-29 - Rust MCP Tools Fixes

## Correzioni applicate
- Ripristinata la compilazione dei tool `debug_mark`, `debug_clean`, `debug_instrument`.
- Hardening di `coderide_web_fetch` e `coderide_web_search`:
  - allowlist `http/https`
  - rifiuto di URL con whitespace/control chars
  - URL-encoding corretto delle query di ricerca
- Corretto `coderide_todo_write`:
  - `todos=""` ora svuota davvero la lista
  - tutte le scritture bulk passano sotto lock esclusivo
  - aggiunto parsing checklist `- [ ] ...`
- Hardened `debug_*` file tools:
  - `debug_mark`, `debug_clean`, `debug_instrument` ora rispettano il sandbox del workspace
- Migliorato `debug_test_check`:
  - timeout esplicito `timeout_ms`
  - rilevamento più robusto di `xcworkspace` / `xcodeproj`
  - container Xcode configurabile
- Migliorato `coderide_run_tests`:
  - supporto `workspace`, `project`, `destination`, `timeout_ms`, `timeout_seconds`
  - preferenza per `xcworkspace` quando presente
- Rafforzato il lifecycle backend MCP:
  - buffer delle risposte fuori ordine
  - risposta esplicita alle server-request non supportate
  - raccolta del tail `stderr`
- Allineato il contract test del catalogo al numero reale di tool pubblicati.
- Ridotto l’overhead del path semantico riusando lo snapshot cache completo quando non ci sono filtri.

## Test e validazione
- `cargo test -p coderide_mcp_server_rust` ✅
- `cargo test -p mcp_lifecycle_backend_rust` ✅
- `cargo clippy -p coderide_mcp_server_rust --all-targets --no-deps -- -D warnings` ✅
- `cargo clippy -p mcp_lifecycle_backend_rust --all-targets -- -D warnings` ✅

## Note
- `cargo clippy -p coderide_mcp_server_rust --all-targets -- -D warnings` continua a transitare anche su `solocode_rust_core`, dove restano warning preesistenti fuori dal perimetro di questo batch. Il crate MCP corretto in questo turno è comunque pulito con `--no-deps`.
