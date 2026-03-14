# P3 — review candidate verification tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite engine-side review manteneva ancora `ReviewCandidateVerificationServiceTests.swift` come file dedicato per casi compatibili con `ReviewDiffSummaryServiceTests.swift`.

## Sintomo
- I test del verifier candidate vivevano separati da un altro file di test review service con perimetro analogo e sufficiente capienza residua.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test engine-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/CoderEngineTests/CodeReview`.
2. Verificare la presenza di `ReviewCandidateVerificationServiceTests.swift`.
3. Osservare che contiene solo test service-level compatibili con il file `ReviewDiffSummaryServiceTests.swift`.

## Risultato attuale
- I test candidate verification vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare nello stesso file review service-level, mantenendo una classe `XCTestCase` separata.

## Causa probabile
- Residuo organizzativo dopo il drain dei servizi review.

## Scope consentito
- `ReviewDiffSummaryServiceTests.swift`
- `ReviewCandidateVerificationServiceTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime verifier
- review core Rust

## Moduli confinanti da verificare
- `ReviewCandidateVerificationServiceTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i test candidate verification nel file `ReviewDiffSummaryServiceTests.swift`.
- Mantenere la classe `ReviewCandidateVerificationServiceTests` separata nel file di destinazione.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `ReviewCandidateVerificationServiceTests`

## Commit previsto
- `test(review): fold candidate verification tests into diff summary`
