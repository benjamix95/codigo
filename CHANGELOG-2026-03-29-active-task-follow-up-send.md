# Changelog — 2026-03-29 — Active task follow-up send

## Obiettivo
- Permettere l’invio di messaggi diretti durante l’esecuzione di un task senza richiedere stop manuale.

## Modifiche
- Aggiunta `ComposerSendPolicy` per centralizzare la decisione di dispatch del composer:
  - `fastModeToggle`
  - `standardSend`
  - `interruptAndSendFollowUp`
- Aggiunto helper runtime `sendFollowUpDuringActiveTask()`:
  - se il task corrente e' attivo, esegue `interruptTask(...)`
  - rilancia immediatamente `sendMessage()` sullo stesso thread selezionato
- Aggiornato `handleComposerSend()` per:
  - usare la nuova route policy
  - impedire submit incoerenti in `planningState == .awaitingChoice`
  - mantenere invariato il comportamento di `/fast`
- Aggiornato il composer:
  - `sendButton` non dipende piu' da `!isLoading`
  - i `runtimeControls` mostrano anche il bottone invio durante il task attivo
  - help text del bottone invio adattato al caso follow-up

## Regressioni coperte
- route `task running -> interruptAndSendFollowUp`
- route `idle -> standardSend`
- route `/fast -> fastModeToggle`
- blocco submit in `awaitingChoice`
- requisito di project context per l’azione UI di invio

## Test eseguiti
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerSendPolicyTests`

## File toccati
- `App/SoloCodeApp/Sources/Services/ChatComposer/Support/ComposerSendPolicy.swift`
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_TaskInterjection.swift`
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartH_ComposerMode.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Attachments.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+ComposerBox.swift`
- `Tests/SoloCodeAppTests/ComposerSendPolicyTests.swift`
- `docs/bugfix-records/2026-03-29-active-task-follow-up-send.md`
