# P2 — Il contatore fasi del card review era incrementale invece che decrementale

## Bug Fix Record
- Categoria: B
- Bug: il card di stato review mostrava il contatore fasi come sequenza incrementale (`Preparazione fix = Fase 4 di 5`) invece del countdown richiesto dall’UX.
- Sintomo: la numerazione visibile appariva “al contrario” rispetto all’ordine percepito dall’utente.
- Impatto: progressione confusa nel card `Findings`.
- Gravita': media.
- Steps to reproduce:
  1. Aprire il tab `Findings`.
  2. Portare la review in `Preparazione fix`.
  3. Osservare il badge `Fase 4 di 5` invece del countdown atteso.
- Risultato attuale: il contatore deve essere decrementale.
- Risultato atteso:
  - `Avvio` = `Fase 5 di 5`
  - `Controlli` = `Fase 4 di 5`
  - `Verifica` = `Fase 3 di 5`
  - `Preparazione fix` = `Fase 2 di 5`
  - `Risultati pronti` = `Fase 1 di 5`
- Causa probabile: mapping user-facing riusato dal contatore progressivo interno.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift`
- Verifica post-fix:
  - `xcodebuild -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' build`
- Commit previsto: `fix(review): make review card step counter decremental`
