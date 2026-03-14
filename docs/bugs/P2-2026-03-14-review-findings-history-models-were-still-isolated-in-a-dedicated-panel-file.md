# P2 — review findings history models were still isolated in a dedicated panel file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il pannello history review manteneva ancora `ReviewPanelFindingsHistoryModels.swift` come file Swift non-UI separato per filtri, helper derivati e live board state già usati quasi esclusivamente dalle view history.

## Sintomo
- I tipi history erano separati dalle view history che li consumano direttamente.

## Impatto
- Debito Swift legacy del panel review più alto del necessario.
- Ownership del flusso history distribuita in un file modello residuale.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `App/SoloCodeApp/Sources/Panels/CodeReview/Models`.
2. Verificare la presenza di `ReviewPanelFindingsHistoryModels.swift`.
3. Osservare che i tipi del file sono referenziati quasi solo dalle view history e dal relativo store.

## Risultato attuale
- Filtri, helper e live board state vivevano in un file separato residuale.

## Risultato atteso
- I tipi history devono stare accanto alle view history che li espongono, riducendo frammentazione e debito legacy.

## Causa probabile
- Il cutover panel-side ha drenato prima store e wrapper, lasciando questo file modello come residuo.

## Scope consentito
- `ReviewPanelFindingsHistoryTab.swift`
- `ReviewPanelHistoricalFindingDetail.swift`
- `ReviewPanelHistoricalLiveBoard.swift`
- `ReviewPanelFindingsHistoryModels.swift`
- test history panel correlati
- progetto Xcode
- docs cutover review

## Non-scope
- logica store non legata allo storico
- altre view del panel
- runtime Rust

## Moduli confinanti da verificare
- `ReviewPanelFindingsHistoryTests`
- build `Solo Code-Debug`
- boundary guard review panel

## Test da aggiungere o aggiornare
- regressione sui derivati history (`historyBucket`, `latestLifecycleLabel`, filtri)

## Strategia di fix minimo
- Spostare i filtri nella tab history.
- Spostare gli helper derivati di `HistoricalFindingRecord` nel detail history.
- Spostare i tipi live board nel file della live board.
- Eliminare il file modello dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `Solo Code-Debug`
- subset verde di `ReviewPanelFindingsHistoryTests`

## Commit previsto
- `refactor(review): fold findings history panel models into history views`
