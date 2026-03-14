# P2 - Lo stream text accumulator review restava isolato in un file streaming dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewStreamTextAccumulator.swift` restava un file Swift non-UI dedicato nel dominio review core pur contenendo solo un piccolo accumulator di testo stream.
- Sintomo: la logica per comporre `textDelta` e `textReplace` viveva in un file streaming standalone.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/Streaming/CodeReviewStreamTextAccumulator.swift`.
  2. Verificare che il file contenga solo il piccolo accumulator usato dal provider review.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: l'accumulatore stream viveva in un file dedicato.
- Risultato atteso: il tipo deve stare in `CodeReviewMultiSwarmProvider+Types.swift`, accanto agli altri helper core del provider.
- Causa probabile: tranche precedenti avevano drenato wrapper e helper review piu' grandi, lasciando questo tipo residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - session state
  - UI panel
- Moduli confinanti da verificare:
  - `CodeReviewStreamTextAccumulatorTests`
  - `CodeReviewMultiSwarmProvider+Parsing`
  - `CodeReviewMultiSwarmProvider+Fixes`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente dell'accumulatore riutilizzata
- Strategia di fix minimo:
  - spostare `CodeReviewStreamTextAccumulator` in `CodeReviewMultiSwarmProvider+Types.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-stream-accumulator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-stream-accumulator-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-stream-accumulator-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-stream-accumulator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-stream-accumulator-source-packages" -only-testing:CoderEngineTests/CodeReviewStreamTextAccumulatorTests`
- Commit previsto: `refactor(review): fold stream text accumulator into provider types`

## Fix applicato
- `CodeReviewStreamTextAccumulator` spostato in `CodeReviewMultiSwarmProvider+Types.swift`
- rimosso `CodeReviewStreamTextAccumulator.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
