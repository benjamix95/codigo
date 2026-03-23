## Bug Fix Record
- Categoria: A - Critico
- Bug: il server MCP `coderide` esportava i tool con `input_schema` vuoto (`{ type: object, properties: {} }`), quindi Codex vedeva i tool ma non sapeva quali argomenti passare.
- Sintomo: Codex tentava tool come `coderide_read` o `coderide_todo_write` senza parametri obbligatori, causando chiamate fallite o ricaduta su tool interni.
- Impatto: anche con il server MCP correttamente collegato, i tool di progetto risultavano di fatto inutilizzabili dal modello.
- Gravità: P1
- Steps to reproduce:
  1. Esporre `coderide` a Codex via MCP.
  2. Chiedere a Codex di usare `coderide_read` o altri tool core.
  3. Osservare che gli arguments risultano vuoti o incompleti.
- Risultato attuale: i tool vengono elencati ma con schema input privo di campi/required.
- Risultato atteso: i tool core devono pubblicare almeno i parametri minimi richiesti (`path`, `task`, `goal`, `hash`, ecc.).
- Causa probabile: `ToolDefinition::new` nel protocollo MCP inizializzava sempre `input_schema` a un oggetto vuoto e il catalogo Rust non sovrascriveva mai quello schema per i tool concreti.
- Scope consentito:
  - `Native/AppCoreProtocol/src/mcp.rs`
  - `Native/CoderideMCPServerRust/src/catalog.rs`
  - `Native/CoderideMCPServerRust/src/tool_schema.rs`
  - test Rust del catalogo
- Non-scope:
  - refactor completo del protocollo `codex app-server`
  - copertura schema totale per ogni singolo tool migrato
- Moduli confinanti da verificare:
  - `tools/list` del server MCP Rust
  - uso di `coderide_read`, `todo_write`, `plan_*`, `debug_*`, `subagent_*`, `skill`, `web_*`
- Test da aggiungere o aggiornare:
  - contratto `tools/list` con schema non vuoto per i tool core
- Strategia di fix minimo:
  - introdurre `ToolDefinition::with_schema`
  - associare schema input ai tool core nel catalogo Rust
- Verifica post-fix:
  - `cargo test` su `Native/CoderideMCPServerRust`
  - smoke con `codex app-server` / `mcpServerStatus/list`
- Commit previsto:
  - fix(mcp): publish concrete coderide tool schemas
