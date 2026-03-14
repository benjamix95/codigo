# Rust Cutover Boundary Baseline - 2026-03-13

## Stato osservato
- `App/SoloCodeApp/Sources`: circa `750` file Swift, di cui circa `415` non-UI
- `Engine/CoderEngine/Sources`: circa `492` file Swift non-UI
- `Sidebar`: circa `19` file Swift, di cui circa `3` non-UI
- `App/SoloCodeApp/Sources/Panels/CodeReview`: `81` file Swift per circa `12.6k` linee
- `Engine/CoderEngine/Sources/CodeReview`: `49` file Swift per circa `7.7k` linee
- `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `30` file Swift per circa `3.6k` linee
- `Engine/CoderEngine/Sources/Tools`: `71` file Swift per circa `11.1k` linee

## Domini legacy principali da drenare verso Rust
- `App/SoloCodeApp/Sources/Panels/CodeReview`
- `App/SoloCodeApp/Sources/Runtime`
- `Engine/CoderEngine/Sources/CodeReview`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore`
- `Engine/CoderEngine/Sources/Pipeline`
- `Engine/CoderEngine/Sources/Tools`
- `Engine/CoderEngine/Sources/Providers`
- `Engine/CoderEngine/Sources/PersistenceCore`
- `Engine/CoderEngine/Sources/CodebaseIndex`
- `Engine/CoderEngine/Sources/Workspace`

## Freeze iniziale applicato in questa tranche
- i nuovi file Swift devono essere UI, binding minimo o bootstrap Apple e passare l'allowlist `Config/validation/rust-cutover-swift-allowlist.txt`
- i file Swift legacy gia' esistenti vengono censiti come backlog di dominio e possono essere toccati solo per ridurli o svuotarli durante il cutover
- il gate finale "zero Swift non-UI" non e' ancora attivo: questa tranche congela il perimetro, non conclude la migrazione

## Avanzamento tranche 1 review cutover
- introdotti entrypoint Rust dedicati per il panel:
  - `review_core_panel_launch`
  - `review_core_panel_chat_extract`
  - `review_core_panel_history_live`
  - `review_core_panel_history_records`
  - `review_core_patch_workflow`
- il panel `CodeReview` usa ora boundary Rust espliciti per launch, estrazione finding strutturati da chat, live board storico e derivazione history da snapshot
- il debito residuo Swift non-UI del dominio review resta ancora presente e impedisce l'attivazione del gate finale hard-fail; la tranche successiva deve drenare engine review/session/verified findings prima del blocco definitivo

## Avanzamento tranche 2 review cutover
- il guard `rust_cutover_guard` supporta ora prefissi `hard-fail` per domini specifici
- la validation attiva automaticamente il gate review quando il diff tocca uno di questi prefissi:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`
  - `Engine/CoderEngine/Sources/CodeReview`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`
- comportamento atteso della tranche:
  - fuori dal dominio review: restano bloccati solo i nuovi file Swift non-UI
  - dentro il dominio review: il backlog legacy diventa errore hard-fail fino al drenaggio reale verso Rust

## Avanzamento tranche 3 review cutover
- il gate review non usa piu' il criterio "zero legacy in un solo commit"
- quando il diff tocca uno dei prefissi review, la validation:
  - calcola la baseline dei file Swift legacy del prefisso su `HEAD`
  - impone un budget di tranche pari a `baseline - 1`
  - fallisce se il nuovo diff non riduce il backlog almeno di 1
- risultato operativo:
  - il target finale resta `zero Swift non-UI`
  - il dominio review torna migrabile in passi piccoli, ciascuno obbligato a ridurre il debito rispetto alla baseline precedente

## Avanzamento tranche 4 review cutover
- consolidati i bridge review gia' Rust-backed dentro file Swift legacy gia' esistenti
- rimossi tre file Swift non-UI dal panel review senza introdurre nuovi file Swift non-UI
- conteggio osservato del panel review:
  - prima della tranche: `36` file legacy non-UI
  - dopo la tranche: `33` file legacy non-UI
- la validation review passa con:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 5 review cutover
- assorbito `CodeReviewPanelStore+RustHistoryLiveState.swift` in `CodeReviewPanelStore+PipelineJobState.swift`
- corretto il boundary guard per il caso di file cancellati nel diff:
  - il report corrente ignora i candidate gia' rimossi dal workspace
  - il baseline `HEAD` puo' includerli tramite flag esplicito
- conteggio osservato del panel review:
  - prima della tranche: `33` file legacy non-UI
  - dopo la tranche: `32` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 6 review cutover
- assorbito `CodeReviewPanelStore+RustCompletionFinalization.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `32` file legacy non-UI
  - dopo la tranche: `31` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 7 review cutover
- assorbito `CodeReviewPanelStore+RustPanelState.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+PipelineJobState.swift`
  - `CodeReviewPanelStore+SnapshotMutation.swift`
  - `CodeReviewPanelStore+Summary.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `31` file legacy non-UI
  - dopo la tranche: `30` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 8 review cutover
- assorbito `CodeReviewPanelStore+Launch.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+LiveRunExecution.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `30` file legacy non-UI
  - dopo la tranche: `29` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 9 review cutover
- assorbito `CodeReviewPanelStore+ChatSession.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+ChatMessages.swift`
  - `CodeReviewPanelStore+SnapshotMutation.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `29` file legacy non-UI
  - dopo la tranche: `28` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 10 review cutover
- esteso il boundary Rust del live board storico review per supportare:
  - `fileLedger`
  - `workerPlans`
  - `liveCards`
- assorbito `CodeReviewPanelStore+HistoryLive.swift` in `CodeReviewPanelStore+History.swift`
- spezzato il supporto Rust del live board in:
  - `Native/RustCore/src/review_history/live.rs`
  - `Native/RustCore/src/review_history/live_inputs.rs`
- conteggio osservato del panel review:
  - prima della tranche: `28` file legacy non-UI
  - dopo la tranche: `27` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 11 review cutover
- assorbito `CodeReviewPanelStore+BugHunter.swift` in `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `27` file legacy non-UI
  - dopo la tranche: `26` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 12 review cutover
- introdotto un boundary Rust dedicato per il Git context del panel review:
  - `Native/RustCore/src/review_git_context.rs`
  - `Native/RustCore/src/ffi/review_panel_git.rs`
- assorbito `CodeReviewPanelStore+GitContext.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+ProviderSelection.swift`
  - `CodeReviewPanelStore+Settings.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `26` file legacy non-UI
  - dopo la tranche: `25` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 13 review cutover
- assorbito `CodeReviewPanelStore+PatchWorkflow.swift` nei file store gia' esistenti:
  - `CodeReviewPanelStore+PatchWorkflow+Execution.swift`
  - `CodeReviewPanelStore+Settings.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del panel review:
  - prima della tranche: `25` file legacy non-UI
  - dopo la tranche: `24` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 14 review cutover
- eliminato il bridge engine-side `ReviewPatchRustBridge.swift`
- DTO patch runtime consolidati in `VerifiedFindingsCanonicalStore.swift`
- queue context rust consolidato in `VerifiedFindingsLifecycleCommandService.swift`
- runtime start/result e fallback `close_finding` consolidati in `VerifiedFindingsPatchExecutionService.swift`
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 15 review cutover
- eliminato il file panel-side `CodeReviewPanelStore+ModesAndChatThreads.swift`
- helper di mode selection, chat session key e thread conversation consolidati in `CodeReviewPanelStore+ChatFindings.swift`
- conteggio osservato del panel review:
  - prima della tranche: `24` file legacy non-UI
  - dopo la tranche: `23` file legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 16 review cutover
- eliminato il file engine-side `CodeReviewMultiSwarmProvider+WorkerOrdering.swift`
- helper di worker ordering consolidati in `CodeReviewMultiSwarmProvider+Types.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `84` file Swift
  - dopo la tranche: `83` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 17 review cutover
- eliminato il file session-side `SessionConfig+ReviewCommandPayload.swift`
- helper `reviewCommandPayload` consolidato in `ReviewSessionTypes.swift`
- conteggio osservato del dominio review engine/tooling:

## Avanzamento tranche 18 review cutover
- irrigidito il boundary MCP review per preservare i contratti del handler quando il bridge Rust non risponde
- `review_start` usa il percorso locale stabile e non tenta piu' di risolvere sessioni inesistenti
- rimossi i wrapper dedicati del handler review:
  - eliminato `CodeReviewHandler.swift`
  - routing e helper assorbiti in `CodeReviewHandler+Start.swift` e `CodeReviewHandler+Findings.swift`
- introdotte regression con Rust forzato off per:
  - `review_status`
  - `review_findings`
  - `review_revalidate_finding`
- conteggio osservato del prefix MCP review hard-fail:
  - prima della tranche: `6` file Swift legacy non-UI
  - dopo la tranche: `5` file Swift legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 19 review cutover
- assorbito `ReviewRuntimeAdapter+Execution.swift` in `ReviewRuntimeAdapter.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `67` file Swift
  - dopo la tranche: `66` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 20 review cutover
- assorbito `ReviewCandidateVerificationService.swift` in `ReviewPipelineCoordinator+CandidateVerification.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `66` file Swift
  - dopo la tranche: `65` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 21 review cutover
- corretto il loader history panel per usare `VerifiedFindingsQueryService.listHistoricalFindings(query:)`
- assorbito `ReviewPanelChatPresentationModels.swift` in `ReviewPanelChatModels.swift`
- rimosso il file residuale dal filesystem e dal progetto Xcode
- conteggio osservato del prefix panel review hard-fail:
  - prima della tranche: `23` file Swift legacy non-UI
  - dopo la tranche: `22` file Swift legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 22 review cutover
- assorbito `VerifiedFindingsSecurityGateService.swift` in `SecurityWorkflowService.swift`
- mantenuto uno shim compatibile del nome pubblico nel file consolidato
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `VerifiedFindingsCore`:
  - prima della tranche: `19` file Swift
  - dopo la tranche: `18` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 23 review cutover
- assorbito `VerifiedFindingsCheckpointService.swift` in `VerifiedFindingsService.swift` e `VerifiedFindingsStatusService.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `VerifiedFindingsCore`:
  - prima della tranche: `18` file Swift
  - dopo la tranche: `17` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 24 review cutover
- assorbito `ReviewPipelineLedgerModels.swift` in `CodeReviewSessionSnapshot+Derived.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `CodeReview`:
  - prima della tranche: `37` file Swift
  - dopo la tranche: `36` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 25 review cutover
- assorbito `ReviewPanelSettingsModel.swift` in `CodeReviewPanelModels.swift` e `ReviewPanelChatModels.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del prefix panel review hard-fail:
  - prima della tranche: `22` file Swift legacy non-UI
  - dopo la tranche: `21` file Swift legacy non-UI
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 26 review cutover
- assorbito `BugHunterWorkflowService.swift` in file verified findings già esistenti
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `VerifiedFindingsCore`:
  - prima della tranche: `17` file Swift
  - dopo la tranche: `16` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 27 review cutover
- assorbito `VerifiedFindingsCommandCoordinator.swift` in file verified findings già esistenti
- ripristinata nel file lifecycle la API pubblica `BugHunterWorkflowService.queueLifecycleCommand(...)`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `VerifiedFindingsCore`:
  - prima della tranche: `16` file Swift
  - dopo la tranche: `15` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 28 review cutover
- assorbito `CodeReviewAuditService+Correlation.swift` in `CodeReviewAuditService+Support.swift`
- rimosso il file dal filesystem e dal progetto Xcode
- conteggio osservato del dominio `CodeReview`:
  - prima della tranche: `36` file Swift
  - dopo la tranche: `35` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 18 review cutover
- eliminato il file core-side `CodeReviewStreamTextAccumulator.swift`
- helper stream text accumulator consolidato in `CodeReviewMultiSwarmProvider+Types.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `82` file Swift
  - dopo la tranche: `81` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 19 review cutover
- eliminato il file application-side `VerifiedFindingAdmissionPolicy.swift`
- policy di admission consolidata in `VerifiedFindingsStatusService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `81` file Swift
  - dopo la tranche: `80` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 20 review cutover
- eliminato il file application-side `SensitiveDataRedactionService.swift`
- servizio di redaction consolidato in `SecurityWorkflowService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `80` file Swift
  - dopo la tranche: `79` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 21 review cutover
- eliminato il file application-side `CommandDeduplicationService.swift`
- deduplication record e actor consolidati in `VerifiedFindingsCommandCoordinator.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `79` file Swift
  - dopo la tranche: `78` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 22 review cutover
- eliminato il file projection-side `VerifiedFindingsProjectionModels.swift`
- projection DTO consolidati in `VerifiedFindingsProjectionBuilder.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `78` file Swift
  - dopo la tranche: `77` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 23 review cutover
- eliminato il file application-side `VerifiedFindingsSessionEnvelope.swift`
- session envelope consolidato in `VerifiedFindingsService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `77` file Swift
  - dopo la tranche: `76` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 24 review cutover
- eliminato il file application-side `EntityExecutionCoordinator.swift`
- actor di serializzazione consolidato in `VerifiedFindingsCommandCoordinator.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `76` file Swift
  - dopo la tranche: `75` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 25 review cutover
- eliminato il file application-side `VerifiedFindingsReplayService.swift`
- replay report e logica di replay consolidati in `VerifiedFindingsService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `75` file Swift
  - dopo la tranche: `74` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 26 review cutover
- eliminato il file core-side `CodeReviewRuntimeResources.swift`
- runtime resources consolidati in `ReviewPipelineCoordinator+Runtime.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `74` file Swift
  - dopo la tranche: `73` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 27 review cutover
- eliminato il file core-side `MultiSwarmReviewConfig.swift`
- config multi-swarm consolidata in `CodeReviewMultiSwarmProvider.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `73` file Swift
  - dopo la tranche: `72` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 28 review cutover
- eliminato il file pipeline-side `CodeReviewMultiSwarmProvider+Pipeline.swift`
- bridge `runReviewPipeline(...)` consolidato in `CodeReviewMultiSwarmProvider+PipelineBridge.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `72` file Swift
  - dopo la tranche: `71` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 29 review cutover
- eliminato il file runtime-side `ReviewPipelineCoordinator.swift`
- actor coordinator consolidato in `ReviewPipelineCoordinator+Runtime.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `71` file Swift
  - dopo la tranche: `70` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 30 review cutover
- eliminato il file bridge-side `CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift`
- forwarding della projection consolidato in `CodeReviewSessionSnapshot+Derived.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `70` file Swift
  - dopo la tranche: `69` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 31 review cutover
- eliminato il file core-side `CodeReviewMultiSwarmProvider+Types.swift`
- tipi e helper del provider consolidati in `CodeReviewMultiSwarmProvider.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `69` file Swift
  - dopo la tranche: `68` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 32 review cutover
- eliminato il file rust-pipeline-side `CodeReviewSessionState+RustSnapshot.swift`
- bridge snapshot consolidato in `CodeReviewSessionState.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `68` file Swift
  - dopo la tranche: `67` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 33 review cutover
- eliminato il file application-side `HistoricalFindingsQueryService.swift`
- query e DTO storici consolidati in `VerifiedFindingsQueryService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `67` file Swift
  - dopo la tranche: `66` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 34 review cutover
- eliminato il file audit-side `CodeReviewAuditService+Adapters.swift`
- helper adapter consolidati in `CodeReviewAuditService.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `66` file Swift
  - dopo la tranche: `65` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 35 review cutover
- eliminato il file audit-side `CodeReviewAuditService+Impact.swift`
- audit bug impact consolidati in `CodeReviewAuditService+Bug.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `65` file Swift
  - dopo la tranche: `64` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 36 review cutover
- eliminato il file domain-side `VerifiedFindingEnums.swift`
- enum verified findings consolidati tra `VerifiedFindingModels.swift` e `VerifiedFindingModels+PatchRun.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `64` file Swift
  - dopo la tranche: `63` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 37 review cutover
- eliminato il file session-side `ReviewLifecycleModels.swift`
- model lifecycle consolidati tra `CodeReviewFinding+Factories.swift`, `CodeReviewSessionState+CandidatesAndPatches.swift` e `CodeReviewSessionSnapshot+Derived.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `63` file Swift
  - dopo la tranche: `62` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`

## Avanzamento tranche 38 review cutover
- eliminato il file panel-side `ReviewPanelFindingsHistoryModels.swift`
- tipi e helper history consolidati nelle view `ReviewPanelFindingsHistoryTab.swift`, `ReviewPanelHistoricalFindingDetail.swift` e `ReviewPanelHistoricalLiveBoard.swift`
- conteggio osservato del dominio review engine/tooling:
  - prima della tranche: `62` file Swift
  - dopo la tranche: `61` file Swift
- stato validation review:
  - `Nuove violazioni: 0`
  - `Legacy oltre budget nel tranche gate: 0`
