# P3 — auto code review routing tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite app-side manteneva ancora `AutoCodeReviewRoutingTests.swift` come file dedicato per casi già compatibili con `ProviderFactoryCodeReviewTests`.

## Sintomo
- I test di routing automatico review vivevano separati dai test del provider factory che validano lo stesso boundary app-side review.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/SoloCodeAppTests`.
2. Verificare la presenza di `AutoCodeReviewRoutingTests.swift`.
3. Osservare che il file contiene solo casi di routing app-side compatibili con la suite provider review.

## Risultato attuale
- I test di auto-routing vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare in `ProviderFactoryCodeReviewTests.swift`.

## Causa probabile
- Residuo organizzativo dopo le tranche panel/provider review precedenti.

## Scope consentito
- `ProviderFactoryCodeReviewTests.swift`
- `AutoCodeReviewRoutingTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime provider
- panel UI rendering

## Moduli confinanti da verificare
- `ProviderFactoryCodeReviewTests`
- build `Solo Code-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i casi di auto-routing nel file provider review.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde di `ProviderFactoryCodeReviewTests`

## Commit previsto
- `test(review): fold auto routing tests into provider factory`
