# P1 — Codex fail-open sui tool built-in quando il profilo MCP punta al binario `.build`

## Bug Fix Record
- Categoria: A — Critico
- Bug: il profilo Codex poteva provisionare `coderide` verso `.build/rust-mcp-server/debug/coderide-mcp-server-rust`, ma con `codex app-server` quel binario falliva l'handshake MCP e la sessione continuava senza tool `coderide_*`.
- Sintomo: Codex usava quasi solo `command_execution`, `list_mcp_resources` e `list_mcp_resource_templates`; non usava `coderide_read`, `coderide_grep`, `coderide_subagent_*`, e la timeline non mostrava più l'interleaving MCP atteso.
- Impatto: il main chat Codex degradava ai tool di default, perdeva sub-agent MCP e rompeva il contratto operativo richiesto dal progetto.
- Gravità: P1
- Steps to reproduce:
  1. Aprire una sessione Codex con profilo gestito in `~/Library/Application Support/Solo Code/CLIProfiles/codex/...`.
  2. Verificare che `config.toml` punti `mcp_servers.coderide.command` al binario `.build/rust-mcp-server/debug/coderide-mcp-server-rust`.
  3. Avviare `codex app-server`, fare `config/mcpServer/reload`, poi `thread/start`.
  4. Osservare `mcpServer/startupStatus/updated` per `coderide`.
- Risultato attuale:
  - `coderide` entra in `failed`;
  - errore: `MCP client for 'coderide' failed to start: MCP startup failed: handshaking with MCP server failed: connection closed: initialize response`;
  - `thread/start` continua comunque;
  - `mcpServerStatus/list` mostra `coderide` con `tools: {}`.
- Risultato atteso:
  - `coderide` deve entrare in `ready`;
  - il catalogo deve esporre i tool `coderide_*`;
  - se `coderide` non parte, Codex non deve ricadere silenziosamente sui tool built-in per task workspace-critical.
- Causa probabile:
  - il resolver del profilo Codex sceglieva il binario in base al file più nuovo, quindi poteva preferire la mirror `.build` invece del binario cargo canonico `Native/target/debug/...`;
  - il profilo MCP Codex restava fail-open (`required` assente), quindi il transport continuava anche con handshake MCP fallito.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Paths.swift`
  - `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexProfiles.swift`
  - test `CLIProfileProvisioner`
  - changelog e bug doc
- Non-scope:
  - refactor del transport Codex App Server
  - modifiche a Claude/Gemini
  - redesign dei prompt MCP Codex
- Moduli confinanti da verificare:
  - repair/reseed dei profili Codex
  - `defaultCodexProfilePath`
  - handshake MCP visibile via `mcpServerStatus/list`
- Test da aggiungere o aggiornare:
  - regression test che forza presenza simultanea di `Native/target` e `.build` e verifica la preferenza per `Native/target`
  - assertion sul flag `required = true` nel blocco `mcp_servers.coderide`
- Strategia di fix minimo:
  - far preferire al resolver il binario `Native/target/debug/coderide-mcp-server-rust`;
  - aggiungere `required = true` al profilo Codex generato/riparato;
  - mantenere `.build` solo come fallback.
- Verifica post-fix:
  - probe `codex app-server` con override su `Native/target/...` -> `coderide` entra in `ready`;
  - `CLIProfileProvisionerTests` verdi sul provisioning aggiornato.
- Commit previsto:
  - `fix(codex): prefer cargo mcp binary and require coderide handshake`

## Evidenza raccolta

### Sessioni sane precedenti
- Trace storiche Codex del 2026-03-23 e 2026-03-27 mostrano `mcp_tool_call` su `coderide_read`, `coderide_list_dir` e `coderide_subagent_explorer`.

### Sessioni degradate recenti
- Trace Codex del 2026-03-29 e 2026-03-30 mostrano quasi solo `command_execution` e tool MCP generici (`list_mcp_resources`, `list_mcp_resource_templates`), senza `coderide_*`.

### Probe protocollo app-server
- `config/read` conferma che il profilo Codex legge:
  - `mcp_servers.coderide.command = /Users/benjaminstoica/SoloCode/.build/rust-mcp-server/debug/coderide-mcp-server-rust`
  - `args = ["--workspace", "."]`
- `thread/start` produce:
  - `mcpServer/startupStatus/updated` -> `coderide starting`
  - poi `coderide failed`
  - errore di handshake `initialize response`

### Probe binario MCP
- Il binario `Native/target/debug/coderide-mcp-server-rust` risponde correttamente a:
  - `initialize`
  - `notifications/initialized`
  - `tools/list`
- Forzando `codex app-server` a usare `Native/target/...`, `coderide` entra in `ready`.

## Decisione
- Il fix deve stare nel provisioning del profilo Codex, non nel prompt.
- Il profilo Codex deve diventare fail-closed rispetto al server `coderide`.
