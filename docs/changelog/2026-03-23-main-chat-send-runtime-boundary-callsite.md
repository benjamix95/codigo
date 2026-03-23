# 2026-03-23 — Main chat send runtime boundary call-site

## Cosa cambia

- il call-site residuo del send runtime non costruisce più manualmente `MainChatUIStateBridge`;
- il prewarm/projection del ramo `standardStream` passa ora dal helper condiviso `projectMainChatUISnapshot(...)`;
- con questo passaggio i path principali `stream`, `plan`, `auto-todo` e `send runtime` usano lo stesso boundary helper per la main chat;
- la tranche 3 di centralizzazione della shell-state boundary può considerarsi chiusa in modo pratico.

## File toccati

- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`

## Verifica

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- avanzamento complessivo: `60%`
