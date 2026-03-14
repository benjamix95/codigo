# P3 — review multi-swarm test shell was still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewMultiSwarmProviderTests` manteneva ancora `CodeReviewMultiSwarmProviderTests.swift` come file dedicato che conteneva solo il guscio `XCTestCase`.

## Sintomo
- Il file base non conteneva test, solo la dichiarazione della suite.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewMultiSwarmProviderTests.swift`.
3. Osservare che contiene solo `final class CodeReviewMultiSwarmProviderTests: XCTestCase {}`.

## Risultato attuale
- Il guscio della suite viveva in un file dedicato residuale.

## Risultato atteso
- Il guscio della suite deve stare in uno dei file test già esistenti del provider.

## Causa probabile
- Residuo organizzativo dopo i tagli precedenti sui test review provider.

## Scope consentito
- `CodeReviewMultiSwarmProviderTests.swift`
- `CodeReviewMultiSwarmProviderTests+Outcomes.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime provider
- review core Rust

## Moduli confinanti da verificare
- `CodeReviewMultiSwarmProviderTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento strutturale della suite

## Strategia di fix minimo
- Spostare la dichiarazione `XCTestCase` nel file `+Outcomes`.
- Eliminare il file shell dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewMultiSwarmProviderTests`

## Commit previsto
- `test(review): fold multi-swarm test shell into outcomes`
