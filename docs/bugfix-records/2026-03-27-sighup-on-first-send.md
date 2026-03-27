# SIGHUP on First Send — 2026-03-27

## Bug Fix Record
- Categoria: A
- Bug: l'app poteva fermarsi sotto debugger con `signal SIGHUP` subito dopo il primo invio messaggio.
- Sintomo:
  - dopo l'avvio e il primo send, Xcode fermava il processo su `Thread 1: signal SIGHUP`
  - lo stop avveniva nel `main-thread` mentre l'app stava già avviando runtime/indexing
- Impatto:
  - impossibile usare la chat in debug in modo affidabile
  - falso crash/blocco durante il flusso base di invio messaggio
- Gravità: alta
- Steps to reproduce:
  1. avviare `Solo Code` da Xcode
  2. inviare il primo messaggio in chat
  3. osservare lo stop del processo con `signal SIGHUP`
- Risultato attuale:
  - i signal guards `SIGHUP`/`SIGPIPE` erano installati solo in `applicationDidFinishLaunching`
- Risultato atteso:
  - i signal guards devono essere attivi già nella bootstrap iniziale del processo
- Causa probabile:
  - finestra temporale troppo presto nel lifecycle app: il primo turn/processo figlio può partire prima che il delegate completi l'installazione dei signal guards
- Scope consentito:
  - bootstrap app
  - delegate app
  - helper signal guard
  - test dedicati
- Non-scope:
  - refactor del runtime chat
  - modifiche al flow di send message
  - cambi ai process supervisor oltre al bootstrap segnali
- Moduli confinanti da verificare:
  - `SoloCodeApp`
  - `AppDelegate`
  - nuovo helper signal guard
- Test da aggiungere o aggiornare:
  - contract dei segnali ignorati
  - smoke test idempotenza installazione guard
- Strategia di fix minimo:
  - estrarre i signal guards in helper dedicato
  - installarli in `SoloCodeApp.init()`
  - mantenerli anche in `applicationDidFinishLaunching` come rinforzo
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/AppProcessSignalGuardsTests -only-testing:SoloCodeAppTests/AppDelegateWindowStyleTests`
- Commit previsto:
  - fix(app): install ignored signal guards before app delegate launch

## Bugs trovati

### P1 — Signal guard installato troppo tardi
- `SIGHUP` e `SIGPIPE` venivano ignorati solo in `applicationDidFinishLaunching`.
- Fix: installazione anticipata in `SoloCodeApp.init()`.

### P2 — Mancanza di un helper riusabile e idempotente
- la logica segnali era inline nel delegate.
- Fix: helper `AppProcessSignalGuards` con installazione idempotente.
