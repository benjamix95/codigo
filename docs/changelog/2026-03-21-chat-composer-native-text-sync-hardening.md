# 2026-03-21 - Chat composer native text sync hardening

## Cosa cambia
- documentato il bug in [P1-2026-03-21-chat-composer-native-text-sync-could-stall-send-state.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-chat-composer-native-text-sync-could-stall-send-state.md)
- il `ComposerNativeNSTextView` pubblica direttamente il testo corrente verso il binding SwiftUI
- il submit con `Return` forza il flush dell'ultimo snapshot del testo nativo prima di chiamare `onSubmit`
- il bottone `Invia` non viene piu` bloccato dal solo `isProviderReady`, così il runtime puo` mostrare feedback esplicito invece di restare muto
- aggiunti test di regressione per sync testo diretto e flush pre-submit

## File principali
- `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTextView.swift`
- `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Attachments.swift`
- `Tests/SoloCodeAppTests/ComposerTextViewFocusTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerTextViewFocusTests -only-testing:SoloCodeAppTests/ChatPanelBuildBehaviorTests`

## Note
- fix confinato al bridge AppKit/SwiftUI del composer e alla UX del bottone di invio
- nessuna modifica al protocollo dei provider o allo streaming
