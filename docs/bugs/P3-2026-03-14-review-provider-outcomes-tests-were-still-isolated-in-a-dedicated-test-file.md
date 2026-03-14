# P3 — review provider outcomes tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewMultiSwarmProviderTests` manteneva ancora `CodeReviewMultiSwarmProviderTests+Outcomes.swift` come file dedicato per casi che possono vivere nel file `+Parsing` senza superare i limiti di dimensione.

## Sintomo
- I test outcomes, ordering e stream accumulator vivevano in un file separato anche se appartengono allo stesso test pack del provider.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test engine-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewMultiSwarmProviderTests+Outcomes.swift`.
3. Osservare che contiene casi compatibili con `CodeReviewMultiSwarmProviderTests+Parsing.swift`.

## Risultato attuale
- I test outcomes vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nello stesso file `+Parsing`, mantenendo una sola dichiarazione `XCTestCase`.

## Causa probabile
- Residuo organizzativo dopo il drain del provider review.

## Scope consentito
- `CodeReviewMultiSwarmProviderTests+Parsing.swift`
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
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i test outcomes nel file `+Parsing`.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewMultiSwarmProviderTests`

## Commit previsto
- `test(review): fold provider outcomes tests into parsing`
