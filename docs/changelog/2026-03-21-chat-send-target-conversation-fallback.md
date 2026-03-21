# 2026-03-21 - Chat send target conversation fallback

## Cosa cambia
- documentato il bug in [P1-2026-03-21-chat-send-silently-dropped-when-no-conversation-selected.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-chat-send-silently-dropped-when-no-conversation-selected.md)
- `sendMessage()` non abortisce piu` in silenzio quando manca la conversazione selezionata
- il submit riusa una conversazione vuota compatibile col contesto oppure ne crea una nuova e la seleziona prima di continuare
- aggiunti test di regressione sulla risoluzione della conversazione target, mantenendo verdi anche i test del bridge composer

## File principali
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessage.swift`
- `Tests/SoloCodeAppTests/ChatPanelBuildBehaviorTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerTextViewFocusTests -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests`

## Note
- fix confinato al percorso di risoluzione della conversazione target per il submit
- nessuna modifica ai provider o alla pipeline di streaming
