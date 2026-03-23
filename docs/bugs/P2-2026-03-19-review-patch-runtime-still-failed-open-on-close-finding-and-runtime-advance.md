# P2 — review patch runtime ancora fail-open su `close_finding` e sugli advance del runtime

## Categoria
- `B` importante ma non bloccante

## Bug
- Il patch workflow review non era ancora fail-closed: se il runtime patch Rust non era disponibile, `VerifiedFindingsPatchExecutionService` poteva ancora chiudere localmente un finding con `close_finding`, e se il bridge `apply_runtime_result` falliva durante l’avanzamento il workflow poteva terminare senza errore esplicito.

## Sintomo
- `close_finding` continuava ad avere un fallback Swift locale.
- L’avanzamento del runtime patch dopo uno step riuscito o fallito non richiedeva obbligatoriamente una risposta valida dal runtime Rust.

## Impatto
- Ownership sdoppiata tra Swift e Rust sul lifecycle patch.
- Failure mode implicito su un’area ad alto rischio che tocca workflow patch e stato dei finding.
- Possibilità di successo apparente del workflow anche con boundary Rust incompleto o indisponibile.

## Gravità
- `P2`

## Steps to reproduce
1. Disabilitare il review core Rust con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
2. Eseguire un’azione patch `close_finding` da command loop o service.
3. Osservare che prima del fix la chiusura del finding poteva ancora avvenire via path Swift locale.

## Risultato attuale
- Prima del fix, `close_finding` aveva un fallback locale in Swift e il risultato del runtime patch non era richiesto in modo stretto dopo ogni step.

## Risultato atteso
- Se il runtime patch Rust non è disponibile o il bridge di avanzamento non risponde, il workflow deve fallire in modo esplicito senza mutazioni locali equivalenti.

## Causa probabile
- Cutover avviato dal planner/runtime Rust ma lasciato con fallback legacy per mantenere compatibilità temporanea.

## Scope consentito
- `Native/RustCore/src/review_patch/models.rs`
- `Native/RustCore/src/review_patch/runtime.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift`
- regressioni app-side patch workflow e command loop close finding

## Non-scope
- Porting completo di `prepare_patch`, `apply_patch`, `rollback_patch`, `open_pr`, `merge_pr`, `resolve_conflicts` in Rust
- Ownership MCP read/write
- UI del panel review

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests+Support.swift`

## Test da aggiungere o aggiornare
- test service-level che `close_finding` fallisce closed con runtime patch Rust disabilitato
- test service-level che il workflow fallisce se `apply_runtime_result` non risponde
- test command-loop che `close_finding` non muta lo snapshot quando il runtime patch Rust è disabilitato
- test Rust sul runtime patch con `completed_steps` e metadati canonici di avanzamento

## Strategia di fix minimo
- arricchire il runtime patch Rust con stato canonico minimo (`steps`, `completed_steps`, `last_transition_at`, `terminal_reason`)
- rimuovere il fallback locale di `close_finding`
- rendere obbligatoria una risposta valida del runtime Rust dopo ogni step

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopCloseFindingTests`

## Commit previsto
- `fix(review-patch): fail closed when rust patch runtime is unavailable`
