# P1 - Il planner del fix-stage review e il bridge eventi worker erano ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo il porting di sessione e provider parsing, il loop `fix-stage` della review continuava a decidere in Swift il batching dei task, il mapping dello scope pipeline e la forma dei payload worker emessi verso il runtime.
- Sintomo: [ReviewPipelineCoordinator+FixStage.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+FixStage.swift) manteneva ancora:
  - grouping non-overlap dei `ReviewTask`
  - mapping `resolvedScope/againstRef -> ReviewScope`
  - trasformazione di `PipelineUIEvent` in eventi `StreamEvent.raw/.textDelta/.textReplace`
- Impatto: il fix-stage host non era ancora Rust-owned sulla parte decisionale del planner/runtime bridge; persisteva rischio di drift fra event model della pipeline e review runtime.
- Gravita': alta, perche' tocca orchestrazione task, lock scheduling e bridge tra pipeline host e runtime review.
- Steps to reproduce:
  1. Ispezionare `runPipelineFixStage(...)` e `bridgePipelineEvent(...)`.
  2. Verificare che batching e payload worker siano calcolati localmente in Swift.
  3. Eseguire `ReviewPipelineCoordinatorTests` senza una source of truth Rust per questi path.
- Risultato attuale: il fix-stage usa ancora logica Swift in un punto sensibile del runtime.
- Risultato atteso: batching task, mapping dello scope e payload worker devono essere serviti dal core Rust; Swift deve limitarsi all’host di esecuzione e al lock I/O.
- Causa probabile: il cutover precedente ha spostato state machine e parser provider, ma non il planner locale del fix-stage.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+FixStage.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - esecuzione reale dei worker via `PipelineFacade`
  - lock acquisition/release I/O
  - patch workflow
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewRuntimeAdapter`
  - `PipelineJobFactory`
- Test da aggiungere o aggiornare:
  - regression sul batching non-overlap
  - regression sulla shape dei payload worker `task_failed`
- Strategia di fix minimo:
  - introdurre boundary Rust per `review_core_fix_stage_plan`
  - introdurre boundary Rust per `review_core_fix_stage_bridge_event`
  - lasciare in Swift solo lock handling, `PipelineFacade.executeJob(...)` e il dispatch dei risultati
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::fix_stage::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-fix-stage): route planner and event bridge through rust`

## Effetto osservato
- Il fix-stage mantiene in Swift solo l’host esecutivo e il lock I/O.
- Planner batch/scope e bridge degli eventi worker sono ora serviti dal core Rust.
- Le regressioni del coordinatore review coprono il nuovo boundary Rust.
