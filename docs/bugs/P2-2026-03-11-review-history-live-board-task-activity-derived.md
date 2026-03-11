# P2 — Findings History live board derivata da TaskActivity invece che dal file ledger canonico

## Bug Fix Record
- Categoria: B
- Bug: il blocco live di `Findings History` derivava principalmente da `TaskActivity` e swarm cards, replicando la semantica di live activity/findings invece di mostrare il ledger canonico dei file assegnati e analizzati.
- Sintomo: `Findings History` appariva come clone di `Findings`/`Live Activity`; i file commissionati e il loro stato reale non erano letti dal contratto canonico della review.
- Impatto: storico poco affidabile, perdita di chiarezza su file/worker/fase, maggiore dipendenza da tracce effimere invece che dallo snapshot canonico.
- Gravita': media, perché degrada osservabilità e chiarezza del review flow.
- Steps to reproduce:
  1. Aprire `Findings History` durante o dopo una review.
  2. Confrontare il live board con activity cards e findings correnti.
  3. Osservare che il contenuto è derivato da worker-plan/task activity e non da un file ledger snapshot-driven.
- Risultato attuale: `Findings History` deve privilegiare `fileLedger` e `phaseLedger` del run, usando `TaskActivity` solo come fallback/telemetry secondaria.
- Risultato atteso: il live board storico mostra file, worker, severità e stato in modo file-centric e coerente con lo snapshot review.
- Causa probabile: implementazione iniziale del live board costruita sul layer TaskActivity prima dell’introduzione del ledger canonico nel review core.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+HistoryLive.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Models/*`
  - reducer Rust panel per file ledger
  - test history live board
- Non-scope:
  - redesign totale dell’archivio storico
  - modifiche DB schema storiche
  - rimozione completa di TaskActivity
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryLiveBoardTests`
  - `ReviewPanelFindingsHistoryTests`
  - `TaskActivityStore+CodeReview`
- Test da aggiungere o aggiornare:
  - regressione live board che usa `fileLedger` quando disponibile
  - regressione sorting severità file nel live board
- Strategia di fix minimo:
  - leggere il ledger snapshot come fonte primaria
  - mantenere il vecchio path TaskActivity solo come fallback
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`
- Commit previsto: `fix(review): source history live board from canonical file ledger`
