# 2026-03-10 — Main window style idempotente

## Obiettivo
Evitare il crash AppKit/KVO quando il chrome della finestra principale viene riapplicato più volte.

## Modifiche
- aggiornato `App/SoloCodeApp/Sources/App/AppDelegate.swift`
  - `applyMainWindowStyle(_:)` ora aggiorna solo le proprietà che non sono già nello stato desiderato
  - `styleMask.insert(.fullSizeContentView)` viene eseguito solo se il flag manca davvero
  - anche `title`, `titleVisibility`, `titlebarAppearsTransparent`, `isOpaque`, `backgroundColor`, `isMovableByWindowBackground`, `toolbarStyle`, `titlebarSeparatorStyle` e `showsBaselineSeparator` sono ora idempotenti
- aggiornato `Tests/SoloCodeAppTests/AppDelegateWindowStyleTests.swift`
  - aggiunto test che richiama `applyMainWindowStyle(_:)` due volte e verifica che il chrome resti valido
- documentato il bug in `docs/bugs/P1-2026-03-10-main-window-style-kvo-crash.md`

## Validazione eseguita
```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/AppDelegateWindowStyleTests
```

## Note
- Il crash report analizzato punta al path AppKit della finestra, non ai warning SwiftUI dei task/review store.
- I warning SwiftUI restano una traccia separata da chiudere con un fix successivo.
