# 2026-03-23 - Chat: placeholder operativi fuori dall'auto-complete, subagent fuori dal gate todo-first

## Cosa cambia
- `todoIDsToAutoCompleteAfterSubagentBatch` ignora i todo con `isOperationalPlaceholder`, cosi' l'auto-complete post-subagent resta ancorato ai task reali
- i tool `coderide_subagent_*` non vengono piu' trattati come lavoro soggetto al gate `todo_first_required`
- aggiunta copertura di regressione per mantenere `policy_ack` nascosto nel feed lineare MCP

## File toccati
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
- `Tests/SoloCodeAppTests/ChatPanelTodoFinalizationTests.swift`
- `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
- `docs/bugs/P2-2026-03-23-chat-todo-placeholder-and-policy-ack-noise.md`

## Verifica
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests CODE_SIGNING_ALLOWED=NO` -> OK
