# P2 - Le action BugHunter del review panel erano ancora isolate in un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+BugHunter.swift` restava come file Swift non-UI dedicato pur contenendo solo due action di enqueue/snapshot per BugHunter.
- Sintomo: il panel review manteneva un file legacy separato per avviare BugHunter da uncommitted o commit window.
- Impatto: il backlog del prefisso review restava piu' alto e il boundary Swift del panel non era ancora consolidato.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+BugHunter.swift`.
  2. Verificare che contenga solo `startBugHunterUncommitted()` e `startBugHunterCommitWindow()`.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: le action BugHunter del panel erano ancora in un file Swift dedicato.
- Risultato atteso: le action panel adiacenti al patch workflow possono vivere in file store esistenti senza mantenere un file legacy separato.
- Causa probabile: tranche precedenti hanno privilegiato launch/chat/history, lasciando indietro il file BugHunter perche' piccolo ma separato.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime BugHunter lato engine
  - UI del panel
  - nuove API Rust
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
  - `ReviewPanelQuickCommands`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - targeted tests `SoloCodeAppTests` lanciati da `scripts/solocode-validate`
- Strategia di fix minimo:
  - assorbire le due action BugHunter in `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PatchWorkflow+Execution.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+BugHunter.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): fold bughunter actions into patch workflow store`

## Fix applicato
- spostate `startBugHunterUncommitted()` e `startBugHunterCommitWindow()` in `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- rimosso `CodeReviewPanelStore+BugHunter.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `27` a `26`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
