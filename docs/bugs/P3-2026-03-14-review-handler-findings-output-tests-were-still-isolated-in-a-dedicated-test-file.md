# P3 — review handler findings output tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewHandlerTests` manteneva ancora `CodeReviewHandlerTests+FindingsOutput.swift` come file test separato per due casi già allineati al perimetro validation del medesimo handler.

## Sintomo
- I test di output `review_findings` erano sparsi su un file dedicato molto piccolo.

## Impatto
- Debito Swift non-UI review più alto del necessario sul lato test.
- Suite handler meno compatta del necessario.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewHandlerTests+FindingsOutput.swift`.
3. Osservare che contiene solo due test strettamente legati alla validation del medesimo handler.

## Risultato attuale
- I test output findings vivevano in un file dedicato residuale.

## Risultato atteso
- I casi `review_findings` devono stare nel file validation già usato dalla stessa suite handler.

## Causa probabile
- Il file era rimasto come residuo dopo tranche precedenti sulla suite MCP review.

## Scope consentito
- `CodeReviewHandlerTests+Validation.swift`
- `CodeReviewHandlerTests+FindingsOutput.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime handler
- review core Rust
- panel UI

## Moduli confinanti da verificare
- `CodeReviewHandlerTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i due test findings output nel file validation.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewHandlerTests`

## Commit previsto
- `test(review): fold findings output tests into validation suite`
