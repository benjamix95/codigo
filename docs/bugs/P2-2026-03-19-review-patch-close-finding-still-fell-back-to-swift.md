# P2 — review patch `close_finding` ancora con fallback Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- Il patch workflow review continuava a chiudere il finding tramite semantica Swift locale nel passo `close_finding`.

## Sintomo
- `VerifiedFindingsPatchExecutionService` applicava `close_finding` con `VerifiedFindingsService.closeFinding(...)` invece di passare da una mutazione Rust dello snapshot.

## Impatto
- `close_finding` restava fuori dal cutover Rust del patch lifecycle.
- Il command loop patch-side poteva ancora chiudere il finding senza ownership Rust reale.

## Gravità
- `P2`

## Steps to reproduce
1. Preparare uno snapshot con finding `merged` o `patch_applied` validato.
2. Eseguire `close_finding` via patch executor o command loop.
3. Osservare che la chiusura veniva applicata localmente in Swift.

## Risultato attuale
- Prima del fix `close_finding` mutava lo snapshot nel layer Swift.

## Risultato atteso
- `close_finding` deve essere applicato da Rust.
- Se il mutator Rust non è disponibile, il workflow deve fallire in modo esplicito.

## Causa probabile
- Fallback temporaneo lasciato nel primo bootstrap del patch executor mentre il runtime Rust copriva solo planning/state-machine.

## Scope consentito
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift`
- test patch workflow app-side

## Non-scope
- `prepare_patch`, `verify_patch`, `apply_patch`, `rollback_patch`, `open_pr`, `merge_pr`, `resolve_conflicts`
- servizi Git/worktree/provider
- MCP handler

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests+Support.swift`

## Test da aggiungere o aggiornare
- gating Rust sul test di successo `close_finding`
- regressione command-loop già presente sul failure mode con runtime Rust disabilitato

## Strategia di fix minimo
- togliere la mutazione Swift locale di `close_finding`
- instradare la chiusura del finding a un mutator Rust dello snapshot
- mantenere invariato il resto del patch workflow

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopCloseFindingTests`

## Commit previsto
- `fix(review-patch): route close finding through rust mutator`
