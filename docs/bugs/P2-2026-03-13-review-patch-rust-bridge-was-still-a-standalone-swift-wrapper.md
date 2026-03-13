# P2 - Il bridge Rust del patch workflow review restava ancora un wrapper Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewPatchRustBridge.swift` restava come file Swift non-UI dedicato nel dominio `VerifiedFindingsCore`, pur inoltrando solo richieste a entrypoint Rust gia' esistenti.
- Sintomo: queue context, runtime start/result e i DTO snapshot/response del patch workflow vivevano ancora in un bridge Swift separato.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy in piu' e il boundary patch review era ancora spezzato tra wrapper inutilmente isolati.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/ReviewPatchRustBridge.swift`.
  2. Verificare che il file esponga solo wrapper `ReviewCoreBridge.call(...)` e DTO serializzabili per il runtime patch.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il patch workflow review aveva ancora un bridge Swift standalone.
- Risultato atteso: i DTO e i call site del patch runtime devono vivere nei file engine/app gia' responsabili di queueing ed esecuzione, senza un file bridge dedicato.
- Causa probabile: tranche precedenti avevano introdotto il boundary Rust ma non avevano ancora consolidato il bridge Swift in punti di ownership piu' corretti.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `App/SoloCodeApp/Sources/CodeReview/Services`
  - `Tests/SoloCodeAppTests`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI del panel review
  - servizi patch generici non toccati dal path review
  - nuovi endpoint Rust
- Moduli confinanti da verificare:
  - `VerifiedFindingsPatchExecutionService`
  - `VerifiedFindingsLifecycleCommandService`
  - `VerifiedFindingsService`
  - `ReviewPatchWorkflowServiceTests`
- Test da aggiungere o aggiornare:
  - `ReviewPatchWorkflowServiceTests`
  - `VerifiedFindingsStartCommandServiceTests`
- Strategia di fix minimo:
  - spostare DTO request/response patch nel canonical store del dominio verified findings
  - spostare queue context rust nel lifecycle command service
  - spostare runtime start/result nel patch execution service
  - riutilizzare `VerifiedFindingsService` per `upsertingPatch` e `closeFinding`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_git_context -- --nocapture`
  - `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests`
- Commit previsto: `refactor(review): fold patch rust bridge into existing engine services`

## Fix applicato
- DTO patch runtime e snapshot rust spostati in `VerifiedFindingsCanonicalStore.swift`
- queue context rust spostato in `VerifiedFindingsLifecycleCommandService.swift`
- runtime start/result e fallback close_finding consolidati in `VerifiedFindingsPatchExecutionService.swift`
- helper `upsertingPatch` e `closeFinding` consolidati in `VerifiedFindingsService.swift`
- aggiornati `ReviewPatchRuntimeFinalizationService` e `ReviewPatchWorkflowServiceTests`
- rimosso `ReviewPatchRustBridge.swift` dal filesystem e dal progetto Xcode

## Esito
- `VerifiedFindingsCore` resta a `29` file Swift nel workspace osservato dopo la rimozione del bridge dedicato
- nessuna nuova violazione Swift non-UI sul dominio review
- build e test mirati review-side restano verdi
