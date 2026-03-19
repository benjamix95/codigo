# P2 — review patch prepare context ancora costruito in Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- La logica che derivava branch name e prompt di `prepare_patch` viveva ancora in Swift dentro `ReviewPatchWorkflowService`, duplicata sui due path con provider registry e provider diretto.

## Sintomo
- `ReviewPatchWorkflowService.preparePatch(...)` e `ReviewPatchWorkflowService+DirectProvider.preparePatch(...)` costruivano localmente:
  - branch name `codex/review-patch-*`
  - prompt di patch preview
- il runtime patch Rust non era ancora owner di questa parte del contesto operativo.

## Impatto
- Ownership ancora sdoppiata su `prepare_patch`.
- Duplicazione tra i due path Swift del workflow patch.
- Failure mode non allineato al boundary Rust per il contesto di preparazione.

## Gravità
- `P2`

## Steps to reproduce
1. Avviare `prepare_patch` da command path o finalizzazione deferred.
2. Osservare che prima del fix il branch name e il prompt venivano derivati localmente in Swift.

## Risultato attuale
- Prima del fix, `prepare_patch` dipendeva da logica Swift per il contesto di esecuzione.

## Risultato atteso
- Il review core Rust deve derivare il contesto minimo di `prepare_patch`, almeno per branch naming e prompt orchestration.

## Causa probabile
- Cutover iniziato dai planner/runtime state ma non ancora esteso alla costruzione del contesto di prepare patch.

## Scope consentito
- `Native/RustCore/src/review_patch/{prepare_context.rs,models.rs,mod.rs}`
- `Native/RustCore/src/ffi/review_patch.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+DirectProvider.swift`
- regressioni mirate su patch workflow e command path

## Non-scope
- Porting completo di `apply_patch`, `rollback_patch`, `merge_pr`, `resolve_conflicts`
- MCP ownership
- UI del panel

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift`
- `Tests/SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests.swift`

## Test da aggiungere o aggiornare
- test Rust del builder `prepare_context`
- test Swift Rust-gated sul prompt di `prepare_patch`
- fail-closed command tests per `prepare_patch` e `verify_patch`
- verifica del path di finalizzazione deferred che continua a passare dal runtime centrale

## Strategia di fix minimo
- aggiungere un builder Rust per il prepare context
- usare quel builder da entrambi i path Swift di `preparePatch`
- mantenere Swift solo come executor di git/worktree/provider nel batch corrente

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`

## Commit previsto
- `refactor(review-patch): derive prepare context in rust`
