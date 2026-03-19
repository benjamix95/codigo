# P1 - Il draft result di `prepare_patch` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: entrambe le varianti `preparePatch(...)` in [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) e [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift) derivavano ancora in Swift il draft artifact della patch.
- Sintomo:
  - `diffPreview` costruito localmente dal `patchText`
  - `riskScore` calcolato localmente
  - `status/verifyStatus/prStatus/mergeStatus` iniziali assegnati localmente
  - duplicazione della stessa semantica in due path app-side diversi
- Impatto: il patch workflow review non era ancora Rust-owned sul boundary di prepare result e manteneva una doppia source of truth Swift.
- Gravita': alta, perche' tocca il lifecycle del patch artifact e l'orchestrazione app-side di `prepare_patch`.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) e [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift).
  2. Cercare il blocco che costruisce `ReviewPatchArtifact` dopo `git diff`.
  3. Verificare che preview, risk score e stati iniziali siano ancora definiti localmente in Swift.
- Risultato attuale: semantica di dominio duplicata e ancora app-side.
- Risultato atteso: il draft artifact deve essere derivato da un reducer Rust unico e Swift deve solo decodificare il payload o fallire chiuso.
- Causa probabile: il porting review aveva già migrato `prepare context`, `verify/apply/revalidate/open_pr result`, ma non l'ultimo blocco di costruzione del draft artifact prima della validation.
- Scope consentito:
  - [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift)
  - [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs)
  - [prepare_result.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/prepare_result.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - validation pipeline della patch
  - git worktree creation/removal
  - provider execution
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `VerifiedFindingsPatchExecutionService`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression app-side sul nuovo bridge `prepare result`
  - regression fail-closed quando il runtime Rust del prepare result non e' disponibile
- Strategia di fix minimo:
  - aggiungere nel core Rust un reducer `build_prepare_result`
  - esporre il boundary `review_core_patch_build_prepare_result`
  - instradare entrambi i callsite Swift `preparePatch(...)` sul bridge Rust comune
  - lasciare in Swift solo git/provider I/O e validation
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::prepare_result::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPreparePatchPromptIncludesVerificationRemediationAndInvariantContext -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPreparePatchContextFailsClosedWhenRustPrepareContextUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareDraftArtifactUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareDraftArtifactFailsClosedWhenRustPrepareResultUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift,App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/prepare_result.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route prepare draft result through rust`

## Effetto osservato
- Il draft artifact di `prepare_patch` e' ora derivato da un boundary Rust unico.
- I due path app-side non calcolano piu' localmente `riskScore`, `diffPreview` e stati iniziali.
- Esistono regressioni dedicate sul bridge positivo e sul fail-closed.
