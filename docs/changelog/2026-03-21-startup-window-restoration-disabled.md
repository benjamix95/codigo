# 2026-03-21 - Startup window restoration disabled

## Cosa cambia
- documentato il bug in [P1-2026-03-21-window-restoration-reopen-loop-crashed-startup.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-window-restoration-reopen-loop-crashed-startup.md)
- disabilitato il save/restore automatico dello stato finestra in `AppDelegate`
- ripulita al launch l'eventuale cartella `Saved Application State` dell'app per evitare crash loop al reopen

## File principali
- `App/SoloCodeApp/Sources/App/AppDelegate.swift`

## Verifica
- `xcodebuild build -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS'`

## Note
- fix di containment sul bootstrap AppKit/SwiftUI
- nessuna modifica al flusso chat o ai provider runtime
