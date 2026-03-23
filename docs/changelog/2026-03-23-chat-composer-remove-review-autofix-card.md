# 2026-03-23 - Rimozione card review/autofix duplicata dal chat composer

## Cosa cambia
- rimosso dal chat composer il blocco UI `Code Review` con toggle `Autofix/Discovery`
- eliminato il wiring locale del composer che passava `showCodeReviewAutofixToggle` e `codeReviewAutofixEnabled`
- lasciati invariati quick commands review, chip modalita' review e panel Code Review dedicato

## File toccati
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Commands.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartH_TaskActivity.swift`
- `Tests/SoloCodeAppTests/ComposerRuntimeTimerTests.swift`
- `docs/bugs/P3-2026-03-23-chat-composer-review-autofix-card-duplicated-panel-control.md`

## Verifica
- `rg -n "showCodeReviewAutofixToggle|codeReviewAutofixEnabled|codeReviewAutofixToggleRow" App/SoloCodeApp/Sources Tests` -> nessun match
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerRuntimeTimerTests CODE_SIGNING_ALLOWED=NO` -> OK
