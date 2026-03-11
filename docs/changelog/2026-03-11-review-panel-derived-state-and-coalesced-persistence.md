# 2026-03-11 - Review panel derived state e snapshot persistence coalesced

## Obiettivo
Rimuovere il lavoro pesante dal `body` SwiftUI del panel Code Review e ridurre la write amplification degli snapshot review verso persistence.

## Modifiche
- aggiornato [CodeReviewPanelStore+Summary.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Summary.swift)
  - il panel legge ora `currentPublishedFindings` e `currentPipelineJobState` dallo stato derivato precalcolato
  - aggiunti `currentReviewPanelDerivedState` e `currentReviewPanelWarmState`
  - integrato il builder memoizzato keyed da `sessionId + mutationSequence`
- aggiornato [ReviewPanelFindingsTab.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingsTab.swift)
  - placeholder non bloccante durante il warming dello stato panel
- aggiornato [TaskActivityStore+CodeReview.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift)
  - l’ingest costruisce uno snapshot con envelope embedded e stato panel derivato già pronto
  - il panel non deve più risolvere verified findings nel render pass
- aggiornato [TaskActivityStore+VerifiedFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift)
  - aggiunti helper per cache derived state
  - `verifiedFindingsProjection(for:)` preferisce lo stato derivato in memoria
  - preservato cold-start da envelope persistito per snapshot terminali
- aggiornato [TaskActivityStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift)
  - `scheduleCodeReviewSnapshotIngest(...)` è ora coalesced
  - `TaskActivityPersistenceBridge` coalesca i write per sessione e forza flush solo sui terminal state o su `flush()`
- aggiornato [PersistenceBootstrapService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PersistenceBootstrapService.swift)
  - aggiunto stato non bloccante `idle | warming | ready | failed`
  - aggiunto `beginBootstrapIfNeeded()`
- aggiornato [CodigoApp+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+Persistence.swift)
  - bootstrap persistence avviato via API non bloccante
- aggiornato reducer Rust:
  - [review_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_models.rs)
  - [review_reduce.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_reduce.rs)
  - [ffi.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi.rs)
  - nuova operazione `derive_review_panel_state` con fallback Swift
- aggiornato [PostgresPersistenceStore+VerifiedFindings.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift)
  - persistence verified findings convertita a delta write
  - checkpoint compatto hash-based salvato in `verified_findings_checkpoints`
  - rebuild dell’envelope dalle tabelle normalizzate e dal projection payload
  - placeholder `artifact_payloads` creati automaticamente per `payloadRef` / `artifactRef` legacy orfani
- aggiornato state engine review:
  - [CodeReviewSessionState.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState.swift)
  - [CodeReviewSessionState+Lifecycle.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState+Lifecycle.swift)
  - callback `onStateChange` coalesced per eventi rumorosi di worker/audit/stage
- aggiornato shaping panel lato Rust/UI:
  - [CodeReviewPanelModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift)
  - [CodeReviewPanelStore+Summary.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Summary.swift)
  - [ReviewPanelFindingsTab.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingsTab.swift)
  - [review_reduce.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_reduce.rs)
  - il reducer ora produce ordering, severity buckets e placeholder già pronti per il render
- aggiornato schema persistence:
  - [PersistenceSchema.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema.swift)
  - [PersistenceSchema+VerifiedFindings.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+VerifiedFindings.swift)
  - versione schema portata a `2`
  - aggiunte colonne `payload` per `pipeline_runs`, `findings`, `evidence`, `verification_reports`, `patch_artifacts`, `revalidation_reports`
- corretto un blocco esterno di build in [CodeReviewHandler+PatchWorkflow.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift)
  - chiusa una graffa mancante che impediva la compilazione del target `CoderIDEMCPServer`

## Test e verifica
- verde:
  - `cargo test -q derive_review_panel_state_marks_hidden_findings_until_patch_ready`
  - `cargo test -q merge_history_prefers_newer_and_resume_eligible`
- build + test app-side:
  - la suite mirata arriva alla fase di build e di esecuzione test
  - l’ambiente locale resta però instabile per un errore esterno di Xcode Launch Services (`IDELaunchServicesLauncher`, `childPID > 0`, `Failed to send resume to target process`)
- note:
  - `cargo test -q` completo del crate Rust continua a mostrare 2 failure preesistenti in `review_patch::runtime`
  - i test engine `CodeReviewSessionStateTests` selezionati mostrano mismatch storici preesistenti su `fixApplied/patchApplied`, non introdotti da questa tranche
  - aggiunta regressione delta write in [MCPSharedStatePostgresFallbackTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Persistence/MCPSharedStatePostgresFallbackTests.swift)
  - aggiunte regressioni in:
    - [PersistenceBootstrapIntegrationTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift)
    - [CodeReviewSessionStateTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests.swift)

## Impatto atteso
- niente più resolve verified findings/pipeline sul render path del tab Findings
- feedback visivo più rapido quando parte la review
- minore pressione sul bridge persistence grazie al coalescing degli snapshot
- persistence review già spostata su delta write reali per verified findings
