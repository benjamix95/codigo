# P1 — verified findings lifecycle queue cadeva ancora sulla queue Swift locale

## Categoria
- `A` critico

## Bug
- [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift) continuava a usare enqueue locale Swift anche dopo la preflight Rust del `queue_context`.

## Sintomo
- `queueFindingCommand(...)` e `queueApplyPatchCommand(...)` validavano o interrogavano il contesto Rust, ma poi accodavano ancora con `MCPSharedState.enqueueCodeReviewCommand(...)`.

## Impatto
- Ownership ancora sdoppiata su un punto critico del workflow verified findings.
- Se la queue Rust non era disponibile, il service poteva ancora ricadere sul path Swift locale invece di fallire closed.

## Gravità
- `P1`

## Steps to reproduce
1. Forzare `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
2. Chiamare `VerifiedFindingsLifecycleCommandService.queueFindingCommand(...)`.
3. Prima del fix, osservare che il service non falliva subito per indisponibilità del runtime patch/queue Rust.

## Risultato attuale
- Prima del fix, la queue lifecycle non era ancora rust-only.

## Risultato atteso
- Il service deve usare solo:
  - `review_core_patch_workflow` per `queue_context`
  - queue Rust-only per l’enqueue reale
- Se uno dei due manca, deve fallire closed.

## Causa probabile
- Il cutover precedente aveva spostato i wrapper MCP, ma non ancora il service engine-side che continua a fare da adapter lifecycle per finding/patch commands.

## Scope consentito
- [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift)
- [VerifiedFindingsStartCommandServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift)
- [CodeReviewHandler+PatchWorkflow.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewHandler+PatchWorkflow.swift)
- `docs/bugs`
- `docs/changelog`

## Non-scope
- Migrazione completa dei `24` file residui in `Engine/CoderEngine/Sources/CodeReview`
- Porting dei modelli domain `VerifiedFindingModels*`
- UI panel

## Moduli confinanti da verificare
- `VerifiedFindingsStartCommandServiceTests`
- wrapper review MCP che mappano `VerifiedFindingsLifecycleCommandError`

## Test da aggiungere o aggiornare
- test fail-closed del lifecycle queue quando il runtime patch Rust non è disponibile
- test nominali Rust-gated per `close_finding`

## Strategia di fix minimo
- eliminare il fallback enqueue Swift locale dal service
- usare `enqueueCodeReviewCommandRustOnly(...)`
- mappare gli errori `queue_context` Rust nell’enum Swift

## Verifica post-fix
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsLifecycleCommandFailClosedTests`

## Commit previsto
- `fix(verified-findings): fail closed on rust lifecycle queue unavailability`
