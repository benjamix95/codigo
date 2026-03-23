# 2026-03-23 - Chat native MCP resource discovery before todo

## Modifiche
- aggiornato il gate `todo_first_required` per trattare `list_mcp_resources`, `list_mcp_resource_templates` e le forme canoniche `mcp_list_resources` / `mcp_list_prompts` come discovery non mutativa.
- aggiunto un test di regressione che verifica l'assenza di violazione policy per tutte e quattro le varianti della tool call di resource discovery.
- documentato il bug con record completo in `docs/bugs`.

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests CODE_SIGNING_ALLOWED=NO`
