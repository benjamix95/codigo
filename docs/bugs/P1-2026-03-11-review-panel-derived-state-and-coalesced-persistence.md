# P1 - Review panel con getter hot-path su main thread e snapshot storm persistito

## Bug Fix Record
- Categoria: A
- Bug: il panel Code Review derivava `published findings` e `pipeline status` nel `body` SwiftUI, mentre l’ingest persistente della review produceva uno snapshot per ogni micro-mutazione.
- Sintomo: freeze o jank evidente nel tab Findings; avvio review con UI lenta; write amplificati verso persistence review.
- Impatto: degradazione UX sul flusso core di review; rischio alto di blocco UI e di contesa con bootstrap/persistenza.
- Gravità: alta
- Steps to reproduce:
  1. aprire il panel Code Review
  2. avviare una review con più worker/eventi
  3. restare sul tab Findings mentre arrivano snapshot ravvicinati
  4. osservare freeze/jank e pressione persistence
- Risultato attuale: il render del panel leggeva stato verified findings/pipeline in modo pesante, e la persistence riscriveva snapshot review troppo spesso.
- Risultato atteso: il panel deve leggere solo stato già materializzato; la persistenza deve essere coalesced e fuori dal render path.
- Causa probabile: coupling tra getter SwiftUI, resolve verified findings e persistenza snapshot non coalesced.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/**`
  - `App/SoloCodeApp/Sources/Tasking/Stores/**`
  - `Engine/CoderEngine/Sources/PersistenceCore/**`
  - `Native/RustCore/src/{ffi.rs,review_models.rs,review_reduce.rs}`
  - test `SoloCodeAppTests` mirati
  - documentazione bug/changelog
- Non-scope:
  - refactor completo della persistence Postgres in delta write
  - refactor completo della lifecycle `CodeReviewSessionState`
  - fix delle failure storiche dei test engine non collegate a questa tranche
- Moduli confinanti da verificare:
  - `TaskActivityStore`
  - `CodeReviewPanelStore`
  - `ReviewPanelFindingsTab`
  - `PersistenceBootstrapService`
  - reducer Rust `review_core_reduce_panel_state`
- Test da aggiungere o aggiornare:
  - regressione panel su findings pubblicati e pipeline status da stato derivato
  - regressione ingest cold-start che preserva `commandLog`
  - regressione su persistence bridge coalesced
- Strategia di fix minimo:
  - precalcolo dello stato panel fuori dal `body`
  - cache keyed da `sessionId + mutationSequence`
  - coalescing di ingest e persistenza snapshot
  - fallback cold-start solo per envelope persistito terminale
- Verifica post-fix:
  - `cargo test -q derive_review_panel_state_marks_hidden_findings_until_patch_ready`
  - `cargo test -q merge_history_prefers_newer_and_resume_eligible`
  - `xcodebuild test` mirati arrivano a build/test execution, ma la sessione locale è attualmente bloccata da un crash/asserzione interna di Xcode launch services
- Commit previsto: `fix(review-panel): materialize derived state and coalesce snapshot persistence`

## Fix applicato
- introdotto stato derivato del review panel (`published findings`, `pipeline job state`, projection, warm state) fuori dal render path
- spostato il consumo UI del panel su cache `TaskActivityStore` invece che su `VerifiedFindingsService.resolve(...)` nel `body`
- aggiunto reducer Rust `derive_review_panel_state` su `review_core_reduce_panel_state`
- aggiunto cache keyed da `sessionId + mutationSequence`
- coalesced `scheduleCodeReviewSnapshotIngest(...)` sul next batch invece che 1 update per tick
- coalesced `TaskActivityPersistenceBridge` con flush seriale e flush immediato sui terminal state
- preservato il cold-start da envelope persistito per snapshot terminali senza reintrodurre il read-path nel `body`
