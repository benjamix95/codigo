# P1 - La riduzione di runAuditStage nel review runtime adapter era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo il porting di sessione, provider parsing, fix-stage planner, candidate builders e task candidate reduction, `ReviewRuntimeAdapter.runAuditStage(...)` continuava ancora a ridurre localmente in Swift `audit snapshot`, `candidates`, `promotedFindings` ed `events`.
- Sintomo:
  - `runAuditStage(...)` costruiva ancora il payload callback tramite finding deduplicati, candidate build e reduction locale dello snapshot audit
  - il core Rust non era ancora la source of truth del callback `run_audit_stage`
- Impatto: il runtime review manteneva ancora una semantica Swift nel callback audit, proprio nel punto in cui gli audit entrano nella verification/promotion review.
- Gravita': alta, perche' tocca audit snapshot, promote dei finding e pipeline callback reduction.
- Steps to reproduce:
  1. Ispezionare [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift).
  2. Verificare che `runAuditStage(...)` riduca ancora localmente finding/candidate/audit.
  3. Notare che il core Rust non riceve ancora il reducer canonico di questo callback.
- Risultato attuale: `run_audit_stage` non ancora Rust-owned end-to-end.
- Risultato atteso: Swift deve limitarsi all’host dell’esecuzione audit; il callback canonico deve essere costruito dal core Rust.
- Causa probabile: la tranche precedente ha spostato provider/task/test callback, ma non ancora il path audit.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Runtime.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - audit host execution
  - panel runtime
  - patch workflow end-to-end
  - provider host I/O
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `CodeReviewAuditAdvancedTests`
- Test da aggiungere o aggiornare:
  - regression Rust per reducer `run_audit_stage`
  - regression XCTest sul callback audit runtime
- Strategia di fix minimo:
  - introdurre boundary Rust per `review_core_runtime_reduce_audit_stage`
  - spostare nel core Rust la riduzione di `findings/candidates/promotedFindings/events/audit`
  - lasciare in Swift solo la raccolta `ReviewAuditToolResult` host-side
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::runtime_audit_stage::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-runtime): route audit stage reduction through rust`

## Effetto osservato
- `runAuditStage` non costruisce piu' il payload canonico nel layer Swift.
- Il runtime adapter continua solo a eseguire gli audit host-side e a inoltrare i risultati grezzi al core Rust.
