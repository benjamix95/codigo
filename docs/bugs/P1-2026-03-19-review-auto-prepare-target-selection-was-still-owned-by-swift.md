# P1 - La selezione dei target auto-prepare review era ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: `ReviewPatchRuntimeFinalizationService.autoPrepareEligibleFindingIds(...)` selezionava ancora in Swift i finding eleggibili per auto-prepare, replicando logica di dominio gia' vicina al reducer Rust di finalizzazione.
- Sintomo:
  - filtro su `verifiedAt/verificationReport`
  - filtro su `patchArtifactId`
  - filtro opzionale su `origin`
  erano ancora nel layer app-side.
- Impatto: il patch runtime finalization non era ancora Rust-owned sulla scelta dei target da preparare automaticamente.
- Gravita': alta, perche' tocca il confine tra completion runtime, patch workflow e comando differito review.
- Steps to reproduce:
  1. Ispezionare [ReviewPatchRuntimeFinalizationService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift).
  2. Verificare che `autoPrepareEligibleFindingIds(...)` filtri ancora i finding nel layer Swift.
  3. Notare che il panel usa gia' il reducer Rust per target selection, ma il command loop no.
- Risultato attuale: due path diversi per una decisione di dominio affine.
- Risultato atteso: la selezione auto-prepare deve essere risolta dal core Rust e Swift deve fallire chiuso se il runtime non risponde.
- Causa probabile: il path app-side del command loop non era stato riallineato dopo l’introduzione del reducer Rust usato nel panel.
- Scope consentito:
  - `Native/RustCore/src/review_finalize.rs`
  - `Native/RustCore/src/review_models.rs`
  - `Native/RustCore/src/ffi/review_core.rs`
  - `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchRuntimeFinalizationService.swift`
  - `Tests/SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - esecuzione patch runtime
  - panel patch workflow completo
  - merge/apply/revalidate/rollback workflow
- Moduli confinanti da verificare:
  - `CodigoAppCodeReviewCommandLoopTests`
  - `ReviewPatchRuntimeFinalizationService`
  - reducer Rust `review_finalize`
- Test da aggiungere o aggiornare:
  - regression app-side su origin filter con runtime Rust disponibile
  - regression fail-closed con runtime Rust disabilitato
- Strategia di fix minimo:
  - aggiungere nel core Rust una variante di target selection con `originFilter`
  - esporre il boundary `review_core_select_auto_prepare_targets`
  - instradare `autoPrepareEligibleFindingIds(...)` solo via Rust
- Verifica post-fix:
  - `cargo build --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled`
- Commit previsto: `refactor(review-finalize): route auto-prepare target selection through rust`

## Effetto osservato
- Il command loop review usa ora il core Rust anche per selezionare i target auto-prepare.
- Il path app-side fallisce chiuso quando il runtime Rust non e' disponibile, invece di ricadere su filtri locali Swift.
