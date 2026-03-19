# P2 — review command lifecycle ancora con fallback Swift su live mutation e deferred finalization

## Categoria
- `B` importante ma non bloccante

## Bug
- Il command lifecycle review non era ancora owned al 100% da Rust: le live mutation del `ReviewSessionRegistry` e la finalizzazione deferred del `review_start` continuavano ad avere un fallback semantico Swift.

## Sintomo
- Se il review core Rust non era disponibile dopo l'avvio del command loop, `dismiss`, `comment`, `apply_fix` live e la chiusura deferred di `review_start` potevano ancora riuscire tramite logica Swift locale.

## Impatto
- Ownership sdoppiata tra Swift e Rust.
- I test potevano passare senza garantire davvero il cutover del lifecycle.
- Il failure mode del runtime review restava implicito invece che esplicito.

## Gravità
- `P2`

## Steps to reproduce
1. Avviare una live review session o un `review_start` deferred con review core Rust attivo.
2. Disabilitare il review core con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
3. Eseguire una live mutation (`dismiss`, `comment`, `apply_fix`) oppure lasciare completare il deferred `review_start`.

## Risultato attuale
- Prima del fix, il registry poteva ancora mutare localmente la live session e la finalizzazione deferred poteva ricostruire localmente lo status finale del command.

## Risultato atteso
- Se il review core non è disponibile, il lifecycle command-side deve fallire in modo esplicito senza fallback comportamentali Swift.

## Causa probabile
- Fallback legacy lasciati durante il cutover progressivo per mantenere compatibilità temporanea.

## Scope consentito
- `Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionRegistry.swift`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift`
- test di regressione command-loop e registry

## Non-scope
- Patch workflow completo
- MCP review handlers
- Provider orchestration
- Panel runtime UI

## Moduli confinanti da verificare
- `Tests/CoderEngineTests/CodeReview/ReviewSessionRegistryTests.swift`
- `Tests/SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests.swift`

## Test da aggiungere o aggiornare
- Regressioni engine per `dismiss`, `comment`, `apply_fix` live con runtime Rust disabilitato
- Regressione app-side per finalizzazione deferred che fallisce closed se il runtime Rust sparisce dopo il launch

## Strategia di fix minimo
- Rimuovere il fallback locale nel `ReviewSessionRegistry`.
- Rimuovere il fallback locale nella finalizzazione deferred.
- Aggiungere test di regressione per il failure mode esplicito.

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewSessionRegistryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`

## Commit previsto
- `fix(review-command): fail closed when rust lifecycle runtime is unavailable`
