# [P1] Il server MCP Rust locale non ha ancora parità completa con il runtime Swift legacy

## Contesto
- è stata introdotta una prima tranche del server MCP Rust separato
- il binario espone handshake MCP, catalogo tool e un set iniziale di handler reali

## Sintomo
- non tutti i tool `coderide_*` hanno ancora implementazione funzionale nativa nel nuovo host Rust
- un cutover hard del launcher MCP verso Rust avrebbe causato errori espliciti su tool ancora non migrati

## Impatto
- il target architetturale “solo UI in Swift” non è ancora raggiunto
- un’attivazione forzata senza completare la parità tool introdurrebbe regressioni funzionali nel code panel

## Evidenza
- il server Rust implementa oggi l’intero catalogo di nomi `coderide_*` esposto dal server MCP locale Swift, inclusi:
  - bootstrap MCP
  - `tools/list`
  - `audit_*` coperti dal review core Rust dove supportati
  - `todo_read`
  - `todo_write`
  - `read`
  - `read_range`
  - `create_file`
  - `write`
  - `str_replace`
  - `regex_replace`
  - `list_dir`
  - `glob`
  - `grep`
  - `find_files`
  - `find_symbol`
  - `find_references`
  - `file_outline`
  - `codebase_search`
  - `semantic_search`
  - `git_diff`
  - `diagnostics`
  - `read_lints`
  - `plan_create`
  - `plan_read`
  - `plan_history_read`
  - `plan_step_update`
  - `plan_step_upsert`
  - `plan_step_batch_update`
  - `plan_step_reorder`
  - `plan_step_dependency_set`
  - `plan_set_walkthrough`
  - `plan_request_user_input`
  - `plan_diff`
  - `policy_ack`
  - `mermaid_render`
  - `debug_log`
  - `debug_query`
  - `debug_session`
  - `debug_hypothesize`
  - `debug_timeline`
  - `debug_snapshot`
  - `debug_trace_analyze`
  - `debug_context`
  - `debug_test_check`
  - `debug_mark`
  - `debug_clean`
  - `debug_instrument`
  - `web_fetch`
  - `web_search`
  - `skill`
  - ack IDE/subagent
  - review/security/bughunter con shared state reale su disco, queue commands e risultati MCP osservabili

## Gap residuo
- il gap non è più la copertura dei nomi tool del server MCP locale
- il lifecycle MCP è ora parzialmente migrato:
  - `MCPSessionManager` usa il backend Rust `mcp-lifecycle-backend-rust` per `health`, `listTools`, `callTool`, `callToolRich`, `reconnect`, `restartServer`, `shutdownAll`
  - `resources` e `prompts` restano ancora su path Swift diretto
- restano ancora da migrare fuori da Swift:
  - `resources` / `prompts` MCP e le subscription resource-side
  - runtime locale generale (`UnifiedToolRuntime`)
  - pipeline/code panel/app core
  - fallback e bridge Swift residui fuori dalla sola UI

## Decisione di contenimento
- il launcher `coderide-mcp-server` usa Rust di default
- il rollback al server Swift legacy resta possibile con:
  - `SOLOCODE_USE_SWIFT_MCP_SERVER=1`

## Prossimo passo richiesto
- chiudere `resources/prompts` e spostare fuori da Swift il runtime locale generale, poi il code panel/app core

## Stato
- aperto
