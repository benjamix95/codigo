# 2026-03-23 - Chat native MCP resource discovery before todo

## Modifiche
- aggiornato il gate `todo_first_required` per trattare `list_mcp_resources`, `list_mcp_resource_templates` e le forme canoniche `mcp_list_resources` / `mcp_list_prompts` come discovery non mutativa.
- irrobustita la normalizzazione del nome tool nel gate chat per supportare prefissi come `functions.`, chiavi payload camelCase (`mcpTool`, `toolName`) e tipi evento di discovery diretti.
- aggiunto un test di regressione che verifica l'assenza di violazione policy per tutte e quattro le varianti della tool call di resource discovery.
- estesa la regressione per coprire tool namespaced, payload camelCase e tipi evento diretti.
- documentato il bug con record completo in `docs/bugs`.

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests CODE_SIGNING_ALLOWED=NO`
