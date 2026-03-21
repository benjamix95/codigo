# 2026-03-21 - Chat composer submit binding refresh

## Cosa cambia
- documentato il bug in [P1-2026-03-21-chat-composer-submit-handler-stale-after-view-updates.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-chat-composer-submit-handler-stale-after-view-updates.md)
- il bridge `ComposerTextView` riallinea sempre il `parent` del coordinator durante `updateNSView`
- il bridge aggiorna sempre la closure `onSubmit` del `NSTextView`, evitando callback stantii dopo refresh SwiftUI
- aggiunti test di regressione per submit handler aggiornato e per binding testo aggiornato

## File principali
- `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTextView.swift`
- `Tests/SoloCodeAppTests/ComposerTextViewFocusTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerTextViewFocusTests`
- smoke manuale consigliato: digitazione nel composer, `Return`, click su `Invia`, update UI del composer durante il focus

## Note
- fix confinato al bridge SwiftUI/AppKit del composer
- nessuna modifica alla pipeline di invio messaggi o ai provider runtime
