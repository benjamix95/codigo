# P2 - I test app-side del patch workflow potevano andare in falso `skip` sul core Rust

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift) risolveva il dylib Rust usando `FileManager.default.currentDirectoryPath`, che nel runner `xcodebuild` non e' stabile e poteva mascherare regressioni con `XCTSkip`.
- Sintomo:
  - il test `testOpenPRContextUsesRustContextBuilder` risultava `skipped`
  - il failure path `testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable` non caricava il reducer Rust richiesto dopo la migrazione
- Impatto: la smoke app-side poteva apparire verde pur senza esercitare davvero il boundary Rust del patch workflow.
- Gravita': media, perche' il problema e' di infrastruttura test ma nasconde regressioni reali.
- Steps to reproduce:
  1. Eseguire il test mirato via `xcodebuild`.
  2. Lasciare il resolver basato su `currentDirectoryPath`.
  3. Osservare il `skip` del test `open_pr` o il fallimento del reducer Rust sul path `patch runtime unavailable`.
- Risultato attuale: il runner non risolve in modo affidabile il path del dylib review core.
- Risultato atteso: i test app-side devono calcolare il path dal `#filePath` del test stesso e caricare esplicitamente il runtime Rust.
- Causa probabile: il file di test non era stato ancora riallineato ai resolver `#filePath` gia' introdotti in altre suite review.
- Scope consentito:
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - runtime bridge di produzione
  - provider/app services
  - patch execution semantics
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `CodigoAppCodeReviewCommandLoopTests`
- Test da aggiungere o aggiornare:
  - riallineare `requireReviewCore()` a `#filePath`
  - rendere `testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable` esplicitamente dipendente dal runtime Rust, perche' ora esercita il reducer `mark_patch_prepare_failed`
- Strategia di fix minimo:
  - derivare `repoRoot` da `#filePath`
  - caricare `SOLOCODE_REVIEW_CORE_LIBRARY_PATH` dal path assoluto corretto
  - aggiornare il test failure-path a `async throws` con `try requireReviewCore()`
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsOnlyReturnsVerifiedFilteredOriginsWithoutExistingPatch -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests/testAutoPrepareEligibleFindingIdsFailsClosedWhenRustRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesRoutesThroughPatchExecutionRuntime -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testPrepareVerifiedPatchesFailsClosedWhenPatchRuntimeIsUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testOpenPRContextUsesRustContextBuilder`
- Commit previsto: `refactor(review-patch): route open pr context through rust`

## Effetto osservato
- I test app-side del patch workflow caricano ora il dylib Rust in modo stabile sotto `xcodebuild`.
- Il nuovo test `open_pr` non e' piu' `skipped` e il failure path `prepareVerifiedPatches` verifica davvero il reducer Rust.
