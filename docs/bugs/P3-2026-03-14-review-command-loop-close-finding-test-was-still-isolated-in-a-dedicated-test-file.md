# P3 — review command loop close finding test was still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite app-side del command loop review manteneva ancora `SoloCodeAppCodeReviewCommandLoopCloseFindingTests.swift` come file dedicato per un solo caso compatibile con il file support dello stesso blocco.

## Sintomo
- Il test `close_finding` viveva separato dai provider helper e dai test di command loop correlati.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test app-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/SoloCodeAppTests`.
2. Verificare la presenza di `SoloCodeAppCodeReviewCommandLoopCloseFindingTests.swift`.
3. Osservare che contiene un solo test del medesimo sottodominio command loop review.

## Risultato attuale
- Il test close-finding viveva in un file dedicato residuale.

## Risultato atteso
- Questo test deve stare in `SoloCodeAppCodeReviewCommandLoopTests+Support.swift`.

## Causa probabile
- Residuo organizzativo dopo le tranche command loop review precedenti.

## Scope consentito
- `SoloCodeAppCodeReviewCommandLoopTests+Support.swift`
- `SoloCodeAppCodeReviewCommandLoopCloseFindingTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime command loop
- review core Rust

## Moduli confinanti da verificare
- `SoloCodeAppCodeReviewCommandLoopCloseFindingTests`
- build `Solo Code-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare il test close-finding nel file support.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde del test spostato

## Commit previsto
- `test(review): fold close finding loop test into support`
