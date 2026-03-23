# P1 — I finding BugHunter/Security nel Code Review non erano abbastanza verificati e non aprivano un fix operativo completo

## Categoria
Categoria A per affidabilità del finding, Categoria B per UX operativa del panel

## Bug
Il tab `Findings` del `Code Review` mostrava finding `bugHunter` e `securityAuditor` senza garantire un lifecycle chiuso `verifica reale -> finding pubblicato -> patch preview pronta -> fix diretto dal panel`.

## Sintomo
- la scansione poteva continuare a inseguire fix/re-review via chat anche dopo aver pubblicato i finding
- aprendo una card finding non era garantita la presenza di causa verificata, remediation, invariant/repro e patch diff pronta
- il bottone operativo restava dipendente dalla chat invece che dal detail del finding

## Impatto
- rischio di esporre finding non sufficientemente verificati come se fossero azionabili
- esperienza incoerente tra `Findings` e `Chat`
- maggiore latenza operativa per l’utente, che non poteva entrare nel detail e fare subito `Fix`

## Gravità
Alta

## Causa probabile
Il lifecycle condiviso `VerifiedFindings` era presente, ma il path BugHunter/Security usava ancora uno start review non abbastanza vincolato:
- `analysis_only` non forzato per questi workflow
- nessuna auto-preparazione della patch preview a fine scansione
- parte del contesto di verifica/remediation si perdeva nel mapping `ReviewCandidate -> CodeReviewFinding`

## Fix applicato
- `BugHunterWorkflowService` e `SecurityWorkflowService` ora forzano `analysis_only = true` e richiedono `auto_prepare_verified_patches`
- il command loop del Code Review auto-prepara in serie le patch preview per i soli finding verificati e filtrati per origin
- `CodeReviewFinding` conserva anche `expectedInvariant` e `reproOrReasoning`
- il detail view del finding mostra `Summary`, `Cause / Verification`, `Remediation`, `Invariant / Repro`, `Patch Preview`, `Validation`
- il fix operativo parte dal tab `Findings` con bottone `Fix`, mantenendo la chat come riepilogo e non come entrypoint obbligatorio

## Scope consentito
- engine review / verified findings
- app command loop del Code Review
- detail view dei finding
- test engine e app del workflow review/patch

## Non-scope
- redesign generale del panel
- refactor ampio del reviewer standard oltre all’hardening necessario al lifecycle condiviso

## Moduli confinanti da verificare
- `VerifiedFindingsStartCommandService`
- `ReviewCandidateVerificationService`
- `SoloCodeApp+CodeReviewDeferredCommands`
- `ReviewPatchWorkflowService`
- `ReviewPanelChatMessageContext`

## Test aggiunti o aggiornati
- `CodeReviewFindingTests`
- `VerifiedFindingsStartCommandServiceTests`
- `SoloCodeAppCodeReviewCommandLoopTests`
- `ReviewPanelChatMessageContextTests`
- `ReviewPatchWorkflowServiceTests`

## Verifica post-fix
Eseguita con `xcodebuild` diretto perché `xcodebuildmcp` non è disponibile in questa sessione:
- suite mirata `CoderEngineTests/CodeReviewFindingTests`
- suite mirata `CoderEngineTests/VerifiedFindingsStartCommandServiceTests`
- suite mirata `SoloCodeAppTests/ReviewPanelChatMessageContextTests`
- suite mirata `SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`
- suite mirata `SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

Esito:
- build verde
- test verdi
- nessun redesign extra oltre al detail operativo necessario
