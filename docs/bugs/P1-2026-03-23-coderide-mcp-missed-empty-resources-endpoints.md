## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il server MCP `coderide` non implementava `resources/list` e `resources/templates/list`, quindi Codex `app-server` loggava warning `unsupported method` durante la discovery.
- Sintomo: durante l’uso dei tool MCP comparivano warning su `resources/list` e `resources/templates/list`, pur con i tool funzionanti.
- Impatto: rumore nei log, percezione di integrazione MCP incompleta, e possibile degradazione della discovery lato Codex.
- Gravità: P1 operativa su integrazione, anche se non rompeva i tool core.
- Steps to reproduce:
  1. Avviare `codex app-server` con `coderide` configurato.
  2. Richiedere `mcpServerStatus/list` o lasciare che il manager faccia discovery.
  3. Osservare warning `-32601 unsupported method`.
- Risultato attuale: `coderide` rispondeva solo a `initialize`, `tools/list`, `tools/call`, `ping`.
- Risultato atteso: `resources/list` e `resources/templates/list` devono restituire liste vuote valide quando non ci sono risorse/template.
- Causa probabile: implementazione MCP parziale del server Rust.
- Scope consentito:
  - `Native/AppCoreProtocol/src/mcp.rs`
  - `Native/CoderideMCPServerRust/src/server.rs`
  - `Native/CoderideMCPServerRust/tests/server_smoke.rs`
- Non-scope:
  - aggiunta di vere resource/template surface
  - refactor del protocollo app-server
- Moduli confinanti da verificare:
  - smoke `tools/list`
  - smoke `resources/list`
  - smoke `resources/templates/list`
- Test da aggiungere o aggiornare:
  - `server_smoke` con risposte vuote valide per resources/template
- Strategia di fix minimo:
  - aggiungere i tipi protocollo necessari
  - rispondere con array vuoti invece di `method_not_found`
- Verifica post-fix:
  - `cargo test --test server_smoke initialize_and_list_tools_work`
  - smoke `codex app-server` senza warning MCP resources/templates
- Commit previsto:
  - fix(mcp): answer empty resources endpoints
