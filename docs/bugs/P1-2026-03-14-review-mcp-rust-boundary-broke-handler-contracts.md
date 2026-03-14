# P1 - Il boundary Rust MCP review rompeva i contratti osservabili del handler

## Bug Fix Record
- Categoria: A
- Bug: il boundary `CodeReview` MCP restituiva errori o `Rust review core unavailable` per `review_status`, `review_findings`, `review_list_sessions` e queue actions patch quando il bridge Rust non produceva risposta; inoltre `review_start` tentava di risolvere una `session_id` che non doveva ancora esistere.
- Sintomo: la suite `CodeReviewHandlerTests` falliva in massa; i tool MCP review passavano da output atteso a errori runtime o messaggi di sessione non trovata.
- Impatto: il pannello/handler review MCP perdeva i contratti base di lettura stato e queue command; la tranche review sul prefisso MCP restava bloccata.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `xcodebuild test-without-building ... -only-testing:CoderEngineTests/CodeReviewHandlerTests`.
  2. Osservare failure su `review_status`, `review_findings`, `review_list_sessions`, `review_revalidate_finding`, `review_rollback_patch`, `review_close_finding`.
  3. Osservare `review_start` fallire con `session_id '...' was not found` sul caso duplicate queued start.
- Risultato attuale: il boundary MCP review non degradava correttamente quando il bridge Rust non rispondeva e applicava una risoluzione sessione errata su `review_start`.
- Risultato atteso: i tool MCP review devono preservare i contratti del handler; se il bridge Rust non produce una risposta, il boundary deve fare fallback locale coerente. `review_start` deve validare e queueare senza richiedere una sessione preesistente.
- Causa probabile: il cutover Rust MCP aveva spostato la formattazione/queueing sul bridge senza un fallback locale per i path `nil`, e il support layer riusava la risoluzione sessione anche per il tool di start.
- Scope consentito:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/changelog`
  - `docs/migration`
- Non-scope:
  - UI panel
  - runtime Rust interno del review core
  - persistence schema
- Moduli confinanti da verificare:
  - `CodeReviewHandlerTests`
  - `MCPSharedCodeReviewCommandsTests`
  - `MCP review` boundary hard-fail prefix
- Test da aggiungere o aggiornare:
  - regression test per fallback con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
  - regression esistente `testReviewStartRejectsQueuedDuplicateSessionId`
- Strategia di fix minimo:
  - mantenere `review_start` sul percorso locale stabile
  - introdurre fallback locale per read/queue tools review quando il bridge Rust restituisce `nil`
  - eliminare un file wrapper Swift legacy del prefisso review per rispettare il tranche budget
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Findings.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewRustHandlerSupport.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift,Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+Validation.swift,Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
- Commit previsto: `fix(review): harden mcp handler rust fallback`

## Fix applicato
- spostata la routing surface di `CodeReviewHandler.swift` in file gia' esistenti e rimosso il file dal prefisso review
- `review_start` usa il percorso locale `VerifiedFindingsStartCommandService` senza passare dalla risoluzione sessione del boundary Rust
- `review_status`, `review_findings`, `review_list_sessions` e `review_get_outcome` fanno fallback locale coerente quando il bridge Rust restituisce `nil`
- `review_apply_patch`, `review_revalidate_finding`, `review_rollback_patch` e `review_close_finding` degradano al queue locale dopo la stessa validazione ownership/sessione
- aggiunte regression su fallback forzato con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Esito
- la suite `CodeReviewHandlerTests` torna verde
- il prefix hard-fail `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview` scende da `6` a `5` file Swift legacy
- nessuna nuova violazione Swift non-UI introdotta
