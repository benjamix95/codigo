# P2 - Review patch revalidate/rollback results were still shaped in Swift

## Categoria
- B - Importante ma non bloccante

## Bug
- Il workflow patch review continuava a derivare in Swift lo stato canonico degli artefatti dopo `revalidate_finding` e `rollback_patch`.

## Sintomo
- Dopo una revalidation o un rollback riuscito, `status`, `validation*` e `applyMessage` venivano ricostruiti direttamente in `ReviewPatchWorkflowService+ApplyLifecycle.swift`.

## Impatto
- Il patch runtime Rust non era ancora la source of truth completa per le transizioni artifact-side del workflow patch.
- Il cutover restava fragile: due code path diverse potevano decidere in modo indipendente lo stato finale dell'artefatto.

## Riproduzione
1. Eseguire `revalidate_finding` o `rollback_patch` su una patch già esistente.
2. Osservare che il bridge Rust non veniva consultato per derivare il risultato finale.
3. Verificare che Swift impostava localmente `status`, `validationRunId`, `validationStatus`, `validationSummary` e `applyMessage`.

## Causa probabile
- Le tranche precedenti avevano già spostato in Rust `prepare`, `verify` e `apply`, ma i passi successivi di `revalidate` e `rollback` erano rimasti con shaping locale in Swift.

## Scope consentito
- `Native/RustCore/src/review_patch/**`
- `Native/RustCore/src/ffi/review_patch.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Non-scope
- Orchestrazione provider
- Merge/PR/conflict workflow
- MCP review/security/bughunter

## Fix minimo applicato
- Nuovi builder Rust dedicati per i risultati di `revalidate` e `rollback`.
- Bridge FFI dedicati.
- Routing Swift verso il runtime Rust come path primario con fail-closed.
- Regressioni XCTest e unit test Rust.

## Moduli confinanti verificati
- `ReviewPatchWorkflowService`
- `VerifiedFindingsPatchExecutionService`
- bridge FFI `review_patch`

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
