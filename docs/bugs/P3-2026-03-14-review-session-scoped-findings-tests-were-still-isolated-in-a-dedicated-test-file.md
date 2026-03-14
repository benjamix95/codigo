# P3 — review session scoped findings tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite `CodeReviewSessionStateTests` manteneva ancora `CodeReviewSessionStateTests+ScopedFindings.swift` come file dedicato per tre casi già affini al gruppo terminal/lifecycle della stessa suite.

## Sintomo
- I test sui finding scoped e la mutazione sequence vivevano in un file separato molto piccolo.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `CodeReviewSessionStateTests+ScopedFindings.swift`.
3. Osservare che contiene solo tre test compatibili con la suite lifecycle esistente.

## Risultato attuale
- I test scoped findings vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nel file `CodeReviewSessionStateTests+TerminalLifecycle.swift`.

## Causa probabile
- Residuo organizzativo dopo le tranche session-side precedenti.

## Scope consentito
- `CodeReviewSessionStateTests+TerminalLifecycle.swift`
- `CodeReviewSessionStateTests+ScopedFindings.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime session state
- review core Rust

## Moduli confinanti da verificare
- `CodeReviewSessionStateTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i tre test scoped findings nel file terminal lifecycle.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewSessionStateTests`

## Commit previsto
- `test(review): fold scoped findings tests into terminal lifecycle`
