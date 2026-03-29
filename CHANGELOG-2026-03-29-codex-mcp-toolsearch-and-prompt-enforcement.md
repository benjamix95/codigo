# Changelog - 2026-03-29 - codex mcp toolsearch and prompt enforcement

## Cosa ho cambiato
- aggiunto un prompt provider-specifico per Codex App Server che rende `coderide_*` la superficie MCP canonica per read/search/edit/plan/todo/debug/subagent
- introdotto un parser incrementale dedicato per le righe interne `select:...`, con emissione di raw event `tool_search`
- collegato il parser sia allo streaming `item/agentMessage/delta` sia all'`item/completed`, con deduplica
- nascosto dalla prose chat le righe grezze `select:...` per non sporcare il testo visibile
- aggiunti test Rust per merge prompt e parser `tool_search`
- aggiunto test Swift per il filtro display delle righe `select:...`

## Effetto pratico
- Codex viene guidato in modo molto piu' esplicito verso i tool MCP locali `coderide_*`
- quando Codex fa selection interna dei tool, il bridge puo' mostrare un card `Tool search` invece di perdere l'informazione
- la chat non mostra piu' le righe grezze `select:mcp__...`

## Verifiche previste
- `cargo test` mirato sui moduli `codex_app_server_prompt` e `codex_app_server_tool_search`
- test Xcode mirato `SoloCodeAppTests/ChatStreamFailureHandlingTests`
