# P1 — Nessun timeout sui subprocess nel Rust MCP server

## Bug Fix Record
- Categoria: B - Importante
- Bug: `shell_text` in `diagnostics_tools.rs` e comandi simili in `debug_tools.rs` lanciano subprocess (`cargo check`, `swift build`, `xcodebuild`, `rg`) senza timeout. Un processo bloccato blocca l'intero server MCP (single-threaded).
- Sintomo: Server MCP non risponde più. Nessun tool può essere invocato fino al restart manuale.
- Impatto: Denial of service del server MCP.
- Gravità: P1
- Strategia di fix minimo: Aggiungere un timeout a `shell_text` (es. 120 secondi default, configurabile per tool). Usare `process.wait_timeout()` e terminare il processo se scade.
- Commit previsto: `fix(mcp-rust): add subprocess timeout to shell_text`
