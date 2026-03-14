# P3 — review handler patch lifecycle tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewHandlerTests` manteneva ancora `CodeReviewHandlerTests+PatchLifecycle.swift` come file dedicato per tre casi di patch lifecycle già allineati agli helper della stessa suite.

## Sintomo
- I test `review_revalidate_finding`, `review_rollback_patch` e `review_close_finding` erano separati dal file helper che genera snapshot e patch test.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.
- Suite handler più frammentata del necessario.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewHandlerTests+PatchLifecycle.swift`.
3. Osservare che contiene solo test che dipendono dagli helper della stessa suite.

## Risultato attuale
- I test patch lifecycle vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nel file helper della suite handler review.

## Causa probabile
- Residuo organizzativo dopo le tranche MCP review precedenti.

## Scope consentito
- `CodeReviewHandlerTests+Helpers.swift`
- `CodeReviewHandlerTests+PatchLifecycle.swift`
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
- Spostare i test patch lifecycle nel file helper.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewHandlerTests`

## Commit previsto
- `test(review): fold patch lifecycle tests into handler helpers`
