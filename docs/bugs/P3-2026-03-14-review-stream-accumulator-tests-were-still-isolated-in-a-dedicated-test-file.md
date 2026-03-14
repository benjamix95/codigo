# P3 — review stream accumulator tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite review manteneva ancora `CodeReviewStreamTextAccumulatorTests.swift` come file dedicato per due casi già allineati al gruppo `CodeReviewMultiSwarmProviderTests`.

## Sintomo
- I test dell’accumulatore stream erano separati dal file test outcomes che già copre helper e outcome dello stesso provider.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewStreamTextAccumulatorTests.swift`.
3. Osservare che contiene solo due test minimali sul provider stream accumulator.

## Risultato attuale
- I test dell’accumulatore stream vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nel file outcomes della stessa suite provider.

## Causa probabile
- Residuo organizzativo dopo il drain del provider core.

## Scope consentito
- `CodeReviewMultiSwarmProviderTests+Outcomes.swift`
- `CodeReviewStreamTextAccumulatorTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime provider
- review core Rust

## Moduli confinanti da verificare
- `CodeReviewMultiSwarmProviderTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i due test stream accumulator nel file outcomes.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewMultiSwarmProviderTests`

## Commit previsto
- `test(review): fold stream accumulator tests into provider outcomes`
