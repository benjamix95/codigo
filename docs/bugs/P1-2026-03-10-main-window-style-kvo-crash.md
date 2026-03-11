# P1 — Riapplicare lo style della finestra principale poteva causare abort AppKit/KVO

## Bug Fix Record
- Categoria: A
- Bug: `AppDelegate.applyMainWindowStyle(_:)` riapplicava mutazioni AppKit non idempotenti sulla `NSWindow`, in particolare `styleMask.insert(.fullSizeContentView)`, durante bootstrap e refresh del chrome finestra.
- Sintomo: crash `SIGABRT` con backtrace su `NSWindow.setStyleMask`, `NSTitlebarView viewWillMoveToWindow:` e eccezione KVO `removeObserver:forKeyPath:`.
- Impatto: crash all’avvio o durante i refresh del chrome della finestra principale; interruzione completa dell’app.
- Gravità: alta
- Steps to reproduce:
  1. avviare `Solo Code`
  2. lasciare che il bootstrap richiami `AppDelegate.applyMainWindowStyle(_:)`
  3. forzare ulteriori riapplicazioni del chrome tramite `configureWindow()` o cambio mode/layout
  4. osservare il crash in AppKit
- Risultato attuale: la finestra subiva scritture ripetute su proprietà di chrome già nello stato desiderato, facendo riattivare path interni AppKit sensibili al KVO.
- Risultato atteso: l’applicazione dello style deve essere idempotente; se la finestra è già configurata, i passaggi AppKit costosi non devono essere rieseguiti.
- Causa probabile: `setStyleMask` veniva toccato anche quando `.fullSizeContentView` era già presente; AppKit rientrava in gestione titlebar/KVO e abortiva.
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/AppDelegate.swift`
  - `Tests/SoloCodeAppTests/AppDelegateWindowStyleTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor generale del bootstrap finestra
  - rimozione del refresh chrome da tutti i call site
  - redesign titlebar/sidebar
- Moduli confinanti da verificare:
  - `CodigoApp+Window`
  - `ContentView+Layout+Composition`
  - `WindowSidebarToggleController`
- Test da aggiungere o aggiornare:
  - test idempotenza `applyMainWindowStyle(_:)` richiamato due volte
- Strategia di fix minimo:
  - rendere idempotenti le scritture di chrome (`title`, `titleVisibility`, `titlebarAppearsTransparent`, `styleMask`, `backgroundColor`, `toolbarStyle`, `titlebarSeparatorStyle`, baseline toolbar)
- Verifica post-fix:
  - `SoloCodeAppTests/AppDelegateWindowStyleTests`
- Commit previsto: `fix(window): make main window style application idempotent`

## Evidenza
Crash report:

```text
SIGABRT
AppDelegate.applyMainWindowStyle(_:)
 -> NSWindow.setStyleMask
 -> NSTitlebarView viewWillMoveToWindow:
 -> removeObserver:forKeyPath:
```
