# Changelog — 2026-03-27 — SIGHUP On First Send

## Obiettivo
Ridurre il rischio di stop/crash del processo app su `SIGHUP` durante il primo invio messaggio sotto debugger.

## Modifiche applicate

### Bootstrap segnali anticipato
- Aggiunto [`AppProcessSignalGuards.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Utilities/AppProcessSignalGuards.swift) per centralizzare i segnali ignorati dal processo parent.
- I segnali protetti sono:
  - `SIGHUP`
  - `SIGPIPE`

### Installazione anticipata e idempotente
- Aggiornato [`SoloCodeApp.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Bootstrap/SoloCodeApp.swift) per installare i signal guards già in `init()`, prima che il delegate finisca il bootstrap.
- Aggiornato [`AppDelegate.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/AppDelegate.swift) per richiamare lo stesso helper anche in `applicationDidFinishLaunching` come rinforzo.

### Test
- Aggiunti [`AppProcessSignalGuardsTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/AppProcessSignalGuardsTests.swift) per coprire:
  - elenco segnali attesi
  - idempotenza dell'installazione

## Validazione
- `git diff --check` pulito sui file modificati.
- Avviata validazione mirata con `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/AppProcessSignalGuardsTests -only-testing:SoloCodeAppTests/AppDelegateWindowStyleTests`
- Il fix compila nel perimetro toccato; la build prosegue nella normale compilazione del bundle test.
