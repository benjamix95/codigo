# P2 — `Findings History` senza live board mentre la review è in corso

## Bug Fix Record
- Categoria: B
- Bug: il nuovo tab `Findings History` mostrava solo archivio persistito e `Resume Queue`, ma durante una review attiva non esponeva lo stato live dei file/worker in analisi.
- Sintomo: aprendo `Findings History` mentre il run era in corso, il tab risultava statico o vuoto sul lato operativo; i dettagli live restavano dispersi tra `Findings`, `Commands` e telemetria interna.
- Impatto: UX non enterprise-grade, assenza di visibilità manageriale real-time sul lavoro in corso, percezione di “fermo” mentre la pipeline sta ancora analizzando file.
- Gravità: media
- Steps to reproduce:
  1. Aprire `Findings History`.
  2. Avviare una review con worker plan multipli.
  3. Restare nel tab storico durante l’esecuzione.
  4. Osservare che il tab non mostra file live, worker live e stato run in corso.
- Risultato attuale: storico solo archivio, senza board live.
- Risultato atteso: `Findings History = live board + archive`, con file analizzati in tempo reale, worker status e summary congelato a run concluso.
- Causa probabile:
  - il tab storico era costruito solo intorno alla query DB-first
  - non riusava `review-worker-plan`, `files_raw`, swarm cards e `currentPipelineJobState`
  - il panel store non reagiva ai cambi del `TaskActivityStore`
- Scope consentito:
  - modelli/store/view del tab `Findings History`
  - wiring di refresh live del panel store
  - test UI/state del tab history
  - changelog/bug docs
- Non-scope:
  - redesign completo del tab `Timeline`
  - refactor del tab `Findings` live
  - modifiche al persistence schema
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTab`
  - `CodeReviewPanelStore`
  - `ReviewPanelLifecycleE2ETests`
  - `ReviewPanelProviderSelectionTests`
- Test da aggiungere o aggiornare:
  - `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
  - smoke su `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
- Strategia di fix minimo:
  - derivare `Live Review Board` dal run corrente e da telemetria reale già presente
  - aggiungere file board deduplicato e worker board nel tab storico
  - mantenere l’archive sotto il board e congelare il summary a review completata
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
- Commit previsto: `feat(review): add live board to findings history`
