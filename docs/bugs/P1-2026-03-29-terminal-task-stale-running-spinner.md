# P1 - Task terminale completato ma ancora mostrato come running

## Bug Fix Record
- Categoria: A - Critico
- Bug: alcune sessioni terminale restavano visivamente in esecuzione anche dopo il completamento reale del task.
- Sintomo: la UI continuava a mostrare spinner, etichetta live o stato terminale attivo mentre il task era già chiuso.
- Impatto: stato operativo fuorviante; l'utente vede task apparentemente bloccati o ancora attivi anche quando il modello è andato avanti.
- Gravità: P1
- Steps to reproduce:
  1. Generare una `TaskActivity` terminale con `payload.status = completed`.
  2. Lasciare `activity.isRunning = true` per stato sporco o evento precedente non pulito.
  3. Aprire la card terminale o il task panel.
- Risultato attuale: `TerminalActivitySession` manteneva `isRunning = true` e la view considerava ancora la sessione live.
- Risultato atteso: uno status terminale (`completed`, `failed`, `success`, `done`, `cancelled`, ecc.) deve sempre spegnere la sessione.
- Causa probabile: la normalizzazione dello stato terminale si fidava troppo di `activity.isRunning` e la view ricontrollava anche stringhe di status running in modo ridondante.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Views/TaskActivityPanel/TerminalActivitySession.swift`
  - `App/SoloCodeApp/Sources/Tasking/Views/TaskActivityPanel/TerminalActivitySession+RunningState.swift`
  - `App/SoloCodeApp/Sources/Tasking/Views/TaskActivityPanel/TaskActivityPanel+Terminal.swift`
  - `Tests/SoloCodeAppTests/TerminalActivitySessionTests.swift`
- Non-scope:
  - pipeline eventi
  - reducer chat principale
  - styling della card
- Moduli confinanti da verificare:
  - task panel terminale
  - mapping sessioni terminale da `TaskActivity`
- Test da aggiungere o aggiornare:
  - regressione su `status = completed` con `isRunning = true`
  - regressione sulla normalizzazione `started/completed`
- Strategia di fix minimo: centralizzare la normalizzazione dello stato running della sessione terminale e fare affidamento solo su quello nella UI.
- Verifica post-fix:
  - suite `TerminalActivitySessionTests`
- Commit previsto: `fix(task-terminal): honor terminal completion state in UI`
