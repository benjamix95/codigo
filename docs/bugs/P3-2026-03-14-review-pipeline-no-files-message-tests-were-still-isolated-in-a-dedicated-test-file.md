# P3 — review pipeline no-files message tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite app-side review manteneva ancora `ReviewPipelineNoFilesMessageTests.swift` come file dedicato per casi compatibili con `CodeReviewPanelLiveRunExecutionTests.swift`.

## Sintomo
- I test del messaggio no-files vivevano separati dai test panel review execution dello stesso sottodominio.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test app-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/SoloCodeAppTests`.
2. Verificare la presenza di `ReviewPipelineNoFilesMessageTests.swift`.
3. Osservare che contiene solo casi edge di un helper review già usato dal panel.

## Risultato attuale
- I test del messaggio no-files vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare in `CodeReviewPanelLiveRunExecutionTests.swift`, mantenendo una classe `XCTestCase` separata.

## Causa probabile
- Residuo organizzativo dopo le tranche panel/provider review precedenti.

## Scope consentito
- `CodeReviewPanelLiveRunExecutionTests.swift`
- `ReviewPipelineNoFilesMessageTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime review pipeline
- UI rendering

## Moduli confinanti da verificare
- `ReviewPipelineNoFilesMessageTests`
- build `Solo Code-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i casi no-files nello stesso file di live run execution.
- Mantenere la classe `ReviewPipelineNoFilesMessageTests` separata nel file di destinazione.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde di `ReviewPipelineNoFilesMessageTests`

## Commit previsto
- `test(review): fold no-files message tests into live run execution`
