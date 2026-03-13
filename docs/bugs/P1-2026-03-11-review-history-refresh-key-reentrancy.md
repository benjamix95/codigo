# P1 — Findings History rilanciava refresh DB durante i tick live del pannello review

## Bug Fix Record
- Categoria: A
- Bug: il tab `Findings History` poteva rilanciare `refreshHistoricalFindings()` mentre il live board aggiornava snapshot/task activity, causando publish `@Published` nel turno sbagliato.
- Sintomo: warning `Publishing changes from within view updates is not allowed`, cicli `AttributeGraph`, pannello review instabile e rischio freeze.
- Impatto: comportamento SwiftUI non deterministico durante review live e apertura del tab storico.
- Gravità: alta.
- Steps to reproduce:
  1. aprire il pannello Code Review.
  2. avviare una review con aggiornamenti live su worker/cards.
  3. aprire `History`.
  4. osservare warning SwiftUI e ripetuti refresh dello storico.
- Risultato attuale: il refresh storico veniva agganciato a una chiave volatile collegata anche allo stato live del board.
- Risultato atteso: il refresh automatico dello storico deve dipendere solo dal contesto stabile del pannello e pubblicare stato fuori dal turno di render.
- Causa probabile: `.task(id:)` in `ReviewPanelFindingsHistoryTab` era guidata da chiavi derivate dal live board; in parallelo `refreshHistoricalFindings()` e `refreshGitContext()` facevano publish immediati su `@Published`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+GitContext.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelFindingsHistoryTab.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/CodeReviewPanelView.swift`
  - test e changelog correlati
- Non-scope:
  - redesign del pannello review
  - refactor del live board
  - modifica dei reducer Rust
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryLiveBoardTests`
  - `ReviewPanelFindingsHistoryTests`
  - launch del pannello review
- Test da aggiungere o aggiornare:
  - regressione sulla stabilità della chiave di refresh storico
  - regressione sul caricamento loader-based dello storico
- Strategia di fix minimo:
  - usare una chiave di refresh storico stabile (`workspace + selectedSession`)
  - rimuovere il prefetch history dal root host
  - differire i publish di git/history al tick successivo del main queue
- Verifica post-fix:
  - build `Solo Code-Debug`
  - `AppBundleProjectStructureTests` verde
  - `ReviewPanelFindingsHistory*` eseguiti fino al launcher bug locale di Xcode
- Commit previsto: `fix(review): defer history and git publishes outside view updates`
