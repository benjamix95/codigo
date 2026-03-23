# P2 — review patch snapshot upsert ancora owned da Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- Anche dopo il cutover dei result builder patch, l’esecuzione del patch lifecycle continuava a fare l’upsert canonico di `patches`, `findings` ed `events` in Swift tramite `VerifiedFindingsService.upsertingPatch(...)`.

## Sintomo
- `VerifiedFindingsPatchExecutionService.swift` prendeva artifact già modellati in Rust, ma ricostruiva localmente lo snapshot:
  - inserimento o replace della patch
  - aggiornamento `finding.patchArtifactId`
  - mapping `patch.status -> finding.status`
  - append dell’evento di patch lifecycle

## Impatto
- Ownership ancora sdoppiata sul punto finale del patch lifecycle.
- Il review core Rust decideva il risultato dell’artifact, ma Swift decideva ancora come quello risultato mutava lo snapshot di sessione.
- La tranche 4 non poteva essere dichiarata chiusa finché questo bordo restava locale.

## Gravità
- `P2`

## Steps to reproduce
1. Eseguire un passo patch (`verify_patch`, `apply_patch`, `open_pr`, `merge_pr`, `resolve_conflicts`, `revalidate_finding`, `rollback_patch`).
2. Osservare che il risultato dell’artifact arriva dal review core Rust.
3. Prima del fix, osservare che l’upsert su snapshot e finding status veniva comunque fatto da Swift.

## Risultato attuale
- Prima del fix, il lifecycle patch non era ancora Rust-owned end-to-end sul path di esecuzione.

## Risultato atteso
- L’upsert canonico di `findings`, `patches` ed `events` deve passare da un mutator Rust, lasciando a Swift solo il wiring dello snapshot e il recompute dell’outcome.

## Causa probabile
- Il cutover si era concentrato sui result builder dell’artifact ma non ancora sul consumer che aggiorna lo snapshot di sessione.

## Scope consentito
- `Native/RustCore/src/review_command/{models.rs,mutator.rs}`
- `App/SoloCodeApp/Sources/CodeReview/Services/{ReviewCommandRustBridge.swift,VerifiedFindingsPatchExecutionService.swift}`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Non-scope
- Refactor completo del persistence layer o della replay pipeline
- Porting di tutta la session snapshot logic in Rust
- UI panel

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift`
- `Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift`

## Test da aggiungere o aggiornare
- test Rust del mutator `upsert_patch`
- test Swift sul bridge `upsertPatchSnapshot`
- smoke suite su command loop e provider selection

## Strategia di fix minimo
- estendere il mutator Rust snapshot con azione `upsert_patch`
- far ritornare anche `patches` oltre a `findings` ed `events`
- usare quel mutator nel patch execution service al posto di `VerifiedFindingsService.upsertingPatch(...)`

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`

## Commit previsto
- `refactor(review-patch): route snapshot upsert through rust mutator`
