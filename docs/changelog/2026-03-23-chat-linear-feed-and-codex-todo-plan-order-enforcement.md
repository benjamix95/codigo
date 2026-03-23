# 2026-03-23 - Chat linear feed and Codex todo/plan order enforcement

## Modifiche

- rimossa dalla bubble assistant la resa separata del tool trace
- aggiunto un feed operativo lineare dentro la stessa risposta chat
- ripulite le etichette UI per non mostrare prefissi `MCP call`, `coderide/`, `coderide_*`, `mcp_*`
- introdotto un gate fail-closed per `codex-cli` in `Agent` mode:
  - prima `todo_write`
  - poi `plan_create` o altro evento lifecycle del piano
  - solo dopo il resto delle operazioni

## Verifica

- test logici su invalidazione timeline e prerequisiti `todo -> plan`
- validazione app-side mirata sulle suite chat/todo/plan
