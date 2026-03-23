# 2026-03-23 - Chat: policy error allineati a todo nativa e binding policy_ack

## Cosa cambia
- il messaggio `todo_first_required` ora chiede `todo_write` invece del vecchio `coderide_todo_write`
- gli eventi `policy_ack` vengono trattati come errore solo quando lo status e' davvero `invalid`
- un `policy_ack` senza stato/turno associato non produce piu' il falso errore `Expected hash ?`

## File toccati
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift`
- `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
- `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
- `docs/bugs/P2-2026-03-23-chat-policy-errors-used-stale-todo-copy-and-misclassified-unbound-policy-ack.md`

## Verifica
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests CODE_SIGNING_ALLOWED=NO`
