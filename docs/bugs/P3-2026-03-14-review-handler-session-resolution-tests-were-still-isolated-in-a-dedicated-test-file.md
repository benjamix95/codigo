# P3 — review handler session resolution tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewHandlerTests` manteneva ancora `CodeReviewHandlerTests+SessionResolution.swift` come file dedicato per tre casi di fallback sessione già allineati agli helper della stessa suite.

## Sintomo
- I test session-resolution erano separati dagli helper che costruiscono snapshot e argomenti.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.
- Suite handler più frammentata del necessario.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewHandlerTests+SessionResolution.swift`.
3. Osservare che il file contiene solo tre test che dipendono dagli helper della stessa suite.

## Risultato attuale
- I test di fallback sessione vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nel file helper della suite MCP review.

## Causa probabile
- Residuo organizzativo dopo le tranche MCP review precedenti.

## Scope consentito
- `CodeReviewHandlerTests+Helpers.swift`
- `CodeReviewHandlerTests+SessionResolution.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime handler
- review core Rust

## Moduli confinanti da verificare
- `CodeReviewHandlerTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i tre test session-resolution nel file helper.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewHandlerTests`

## Commit previsto
- `test(review): fold session resolution tests into handler helpers`
