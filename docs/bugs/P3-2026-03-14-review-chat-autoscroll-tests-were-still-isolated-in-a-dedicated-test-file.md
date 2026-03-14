# P3 — review chat autoscroll tests were still isolated in a dedicated test file

## Categoria
- Categoria C — minore / organizzativa

## Bug
- La suite panel chat review manteneva ancora `ReviewPanelChatAutoscrollTests.swift` come file dedicato per tre casi strettamente legati alla feature structured chat.

## Sintomo
- I test degli hash di autoscroll vivevano separati dal file `ReviewPanelChatStructuredContentTests.swift`, pur restando nello stesso sottodominio.

## Impatto
- Debito Swift non-UI review ancora superiore al necessario sul lato test app-side.

## Gravità
- Bassa.

## Steps to reproduce
1. Aprire `Tests/SoloCodeAppTests`.
2. Verificare la presenza di `ReviewPanelChatAutoscrollTests.swift`.
3. Osservare che contiene solo tre test della stessa feature panel chat.

## Risultato attuale
- I test autoscroll vivevano in un file dedicato residuale.

## Risultato atteso
- Questi test devono vivere nello stesso file feature-side, mantenendo una classe `XCTestCase` separata e discoverable.

## Causa probabile
- Residuo organizzativo dopo il drain panel chat-side.

## Scope consentito
- `ReviewPanelChatStructuredContentTests.swift`
- `ReviewPanelChatAutoscrollTests.swift`
- progetto Xcode
- docs cutover review

## Non-scope
- runtime panel chat
- UI rendering

## Moduli confinanti da verificare
- `ReviewPanelChatStructuredContentTests`
- `ReviewPanelChatAutoscrollTests`
- build `Solo Code-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test: si tratta di consolidamento di test esistenti

## Strategia di fix minimo
- Spostare i tre test autoscroll nello stesso file structured content.
- Mantenere una classe `ReviewPanelChatAutoscrollTests: XCTestCase` separata nel file di destinazione.
- Eliminare il file test dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde di `ReviewPanelChatAutoscrollTests`

## Commit previsto
- `test(review): fold chat autoscroll tests into structured content`
