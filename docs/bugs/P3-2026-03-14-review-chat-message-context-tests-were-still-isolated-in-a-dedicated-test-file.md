# P3 — review chat message context tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite panel chat review manteneva ancora `ReviewPanelChatMessageContextTests.swift` come file dedicato per tre casi già affini a `ReviewPanelChatStructuredContentTests.swift`.

## Sintomo
- I test di parsing context e target extraction vivevano separati dai test delle structured sections della stessa feature chat.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test app-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/SoloCodeAppTests`.
2. Verificare la presenza di `ReviewPanelChatMessageContextTests.swift`.
3. Osservare che contiene solo tre test strettamente legati al parsing structured chat.

## Risultato attuale
- I test di message context vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono stare in `ReviewPanelChatStructuredContentTests.swift`.

## Causa probabile
- Residuo organizzativo dopo il drain delle view/model panel chat.

## Scope consentito
- `ReviewPanelChatStructuredContentTests.swift`
- `ReviewPanelChatMessageContextTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime chat panel
- UI rendering

## Moduli confinanti da verificare
- `ReviewPanelChatStructuredContentTests`
- build `Solo Code-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i tre test di context extraction nel file structured content.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde di `ReviewPanelChatStructuredContentTests`

## Commit previsto
- `test(review): fold chat message context tests into structured content`
