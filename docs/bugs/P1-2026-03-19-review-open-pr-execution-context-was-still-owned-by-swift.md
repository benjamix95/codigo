# P1 - L'execution context di `open_pr` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift) decideva ancora in Swift il contesto esecutivo di `open_pr`, cioe' `baseBranch`, `branchName` di fallback e `worktreePath`.
- Sintomo:
  - fallback su `artifact.baseBranchName ?? currentBranch`
  - fallback su `artifact.branchName ?? codex/review-pr-<finding>`
  - costruzione locale del `worktreePath` sotto `NSTemporaryDirectory()`
- Impatto: il patch workflow manteneva ancora semantica app-side nel lifecycle PR, con branching di dominio distribuito nel service Swift.
- Gravita': alta, perche' tocca il command lifecycle `open_pr` e il boundary tra snapshot patch e operazioni Git.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift).
  2. Cercare `func openPullRequest(...)`.
  3. Verificare che `baseBranch`, `branchName` e `worktreePath` siano ancora derivati localmente in Swift.
- Risultato attuale: il contesto esecutivo PR non e' ancora canonicale in Rust.
- Risultato atteso: Swift deve limitarsi a risolvere il `gitRoot/currentBranch` e delegare a Rust la derivazione del contesto `open_pr`, fallendo chiuso se il boundary non risponde.
- Causa probabile: il porting precedente aveva migrato `open_pr context` (`title/body`) e `open_pr result`, ma non il blocco intermedio che decide i parametri del worktree PR.
- Scope consentito:
  - [ReviewPatchWorkflowService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift)
  - [ReviewPatchWorkflowService+DirectProvider.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift)
  - [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs)
  - [open_pr_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/open_pr_execution_context.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - operazioni Git reali di apertura PR
  - merge/conflict resolution
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `ReviewPatchWorkflowService.openPullRequestResult`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression sul nuovo bridge `open_pr execution context`
  - regression fail-closed quando il runtime Rust e' indisponibile
  - smoke sul vecchio `open_pr result` per garantire che il nuovo batch non lo rompa
- Strategia di fix minimo:
  - aggiungere nel core Rust il reducer `build_open_pr_execution_context`
  - esporre il boundary `review_core_patch_build_open_pr_execution_context`
  - instradare `openPullRequest(...)` attraverso un helper Swift fail-closed che usa quel boundary
  - correggere il mismatch DTO `prURL/prUrl` nel request di `open_pr result`
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::open_pr_execution_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPullRequestResultFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift,App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/open_pr_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route open pr execution context through rust`

## Effetto osservato
- Lo step `open_pr` delega ora al core Rust la derivazione del contesto esecutivo PR.
- Swift mantiene solo la risoluzione del `gitRoot/currentBranch` e l'I/O Git effettivo.
- Il vecchio boundary `open_pr result` continua a passare, con il request DTO allineato a `prUrl`.
