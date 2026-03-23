# 2026-03-23 - Chat: plan activation e ordine todo meno aggressivi

## Cosa cambia
- `coderide_activate_plan_mode` e `coderide_activate_debug_mode` non vengono piu' trattati come operazioni soggette al gate `todo_first_required`
- l'auto-activation del plan non forza piu' subito `selectMode(.plan)`
- il trigger `flowStarted` non apre piu' automaticamente il plan panel
- la todo card in chat non si aggancia piu' a uno stub assistant ancora vuoto; aspetta un assistant message visibile

## File toccati
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+UIHelpers.swift`
- `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_AutoActivation.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/Support/ChatPanelView+TodoCardSelection.swift`
- `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
- `Tests/SoloCodeAppTests/PlanShortcutAndCommand/PlanShortcutAndCommandTests+CommandParsing.swift`

## Verifica
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests CODE_SIGNING_ALLOWED=NO` -> OK
