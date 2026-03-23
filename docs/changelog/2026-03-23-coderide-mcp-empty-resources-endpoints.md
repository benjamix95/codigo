## 2026-03-23 - Coderide MCP empty resources endpoints

- Il server MCP Rust `coderide` ora risponde a `resources/list` e `resources/templates/list` con payload vuoti validi invece di `unsupported method`.
- Questo elimina i warning MCP rumorosi visti da Codex `app-server` durante la discovery delle capacità del server.
- Aggiunto smoke test sul server per coprire `tools/list`, `resources/list` e `resources/templates/list`.
