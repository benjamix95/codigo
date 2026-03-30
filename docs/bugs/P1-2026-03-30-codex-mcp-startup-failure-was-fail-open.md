# P1 — Codex app-server proseguiva fail-open quando `coderide` falliva lo startup MCP

## Bug Fix Record
- Categoria: A — Critico
- Bug: il transport `codex_app_server` ignorava gli update `mcpServer/startupStatus/updated` e lasciava partire il turno anche quando `coderide` entrava in stato `failed`.
- Sintomo: Codex sembrava operativo e i test di superficie potevano restare verdi, ma il provider lavorava con tool built-in o MCP generici anziché con `coderide_*`.
- Impatto: regressione silenziosa del flusso Codex; rottura della discoverability reale dei tool MCP locali; rischio di output monolitico e perdita dei subagent.
- Gravità: P1
- Steps to reproduce:
  1. Avviare `codex app-server` con profilo Codex che include `coderide`.
  2. Eseguire `thread/start`.
  3. Osservare notifiche `mcpServer/startupStatus/updated`.
  4. Forzare o incontrare uno startup `failed` per `coderide`.
- Risultato attuale: il transport continuava il flusso e lasciava che Codex ricadesse sui tool built-in o sui tool MCP generici.
- Risultato atteso: uno startup `failed` di `coderide` deve interrompere il flusso Codex in modo esplicito e rumoroso.
- Causa probabile:
  - `codex_app_server.rs` non trattava la notifica `mcpServer/startupStatus/updated`;
  - nessun gate locale distingueva `coderide ready` da `coderide failed`;
  - il parser locale della config Codex loggava `required` come chiave sconosciuta, quindi il path di validazione interna restava rumoroso.
- Scope consentito:
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
  - nuovo helper isolato per startup status MCP Codex
  - parser config MCP Codex locale
  - test Rust/XCTest correlati
- Non-scope:
  - refactor del provider Claude
  - redesign della timeline chat
  - modifica del catalogo `coderide_*`
- Moduli confinanti da verificare:
  - notifiche app-server `mcpServer/startupStatus/updated`
  - parser TOML `mcp_servers.*`
  - repair del config Codex
- Test da aggiungere o aggiornare:
  - test Rust su parsing dello startup status MCP e fail-fast solo per `coderide`
  - test `MCPConfigLoaderParsingTests` per `required` / `tool_timeout_sec`
  - test `CodexCLIProviderInvocationTests` per preservazione del flag `required`
- Strategia di fix minimo:
  - estrarre un helper piccolo e testabile per le notifiche startup MCP;
  - fare `Err(...)` esplicito quando `coderide` entra in `failed`;
  - riconoscere `required` e `tool_timeout_sec` nel parser locale senza warning.
- Verifica post-fix:
  - test Rust helper verdi
  - `CoderEngineTests` mirati verdi
  - `SoloCodeAppTests/CLIProfileProvisionerTests` verdi
- Commit previsto:
  - `test(codex): harden mcp startup fail-fast and config parsing`
