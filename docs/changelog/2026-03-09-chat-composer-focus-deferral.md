# 2026-03-09 — Chat composer focus deferral

## Cosa cambia
- documentato il problema in [P1-2026-03-09-chat-composer-focus-blur-during-view-update.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-09-chat-composer-focus-blur-during-view-update.md)
- il bridge AppKit del composer non forza piu` `makeFirstResponder(...)` inline durante `updateNSView`
- il cambio di focus/blur viene differito sul main queue solo quando lo stato desiderato differisce dal first responder corrente

## File principali
- `App/SoloCodeApp/Sources/Chat/ComposerTextView.swift`

## Verifica
- smoke manuale su auto-focus iniziale del composer
- smoke manuale su blur esplicito e ritorno focus senza perdere il cursore
- controllo regressivo di invio con `Return` e newline con `Shift+Return`

## Note
- priorità documentata: `P1`
- fix confinato al composer bridge SwiftUI/AppKit
- nessuna modifica alla pipeline messaggi o alle shortcut oltre alla sincronizzazione del focus
