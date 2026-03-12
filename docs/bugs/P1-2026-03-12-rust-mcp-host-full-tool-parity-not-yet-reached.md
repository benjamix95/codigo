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
- il server Rust implementa oggi:
  - bootstrap MCP
  - `tools/list`
  - `todo_read`
  - `todo_write`
  - `read`
  - `read_range`
  - `list_dir`
  - `glob`
  - `grep`
  - `find_files`
  - `find_symbol`
  - `find_references`
  - `file_outline`
  - `codebase_search`
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
  - `debug_session`
  - ack IDE/subagent
  - bridge minimo review/security/bughunter
- gli altri tool restano da migrare e rispondono con errore esplicito se invocati nel path Rust

## Decisione di contenimento
- il launcher Swift `coderide-mcp-server` resta il path di default
- l’exec del binario Rust sibling è attivabile solo con:
  - `SOLOCODE_USE_RUST_MCP_SERVER=1`

## Prossimo passo richiesto
- completare la parità dei tool MCP in Rust prima di eliminare il launcher Swift legacy

## Stato
- aperto
