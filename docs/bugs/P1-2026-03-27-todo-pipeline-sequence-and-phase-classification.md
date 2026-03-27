# Bug Fix Record — 2026-03-27 — Todo pipeline sequence and phase classification

- Categoria: A/B misto
- Bug: la pipeline todo generava fasi finali e ordering in modo non coerente con il lavoro reale
- Sintomo:
  - checklist multi-fase mostrate con ordine alterato dallo stato (`pending` / `done`) invece che dalla sequenza logica;
  - `Code Review & Test` poteva essere trattato come default globale invece che come fase reale e condizionale;
  - task analitici o di scan non producevano una struttura finale coerente;
  - i completed restavano visibili, ma potevano apparire fuori posizione nelle superfici che riordinavano localmente.
- Impatto:
  - pipeline todo fuorviante;
  - avanzamento percepito non lineare;
  - prompt e UI non allineati sulla stessa coda;
  - follow-up finali poco difendibili in review.
- Gravità: alta
- Steps to reproduce:
  1. avviare un task multi-fase di analisi o implementazione;
  2. lasciare che il modello/population runtime crei o aggiorni i todo;
  3. osservare card chat, composer overlay e prompt `Current todos`;
  4. completare i primi task e verificare l’ordine dei successivi.
- Risultato attuale:
  - il runtime poteva promuovere il primo `pending` utile senza rispettare sempre i blocchi precedenti;
  - alcune viste e il prompt rimappavano i todo per stato;
  - la policy follow-up si basava su euristiche insufficienti per distinguere fasi reali da placeholder o checklist analitiche.
- Risultato atteso:
  - una sola source of truth per l’ordine;
  - fasi reali e nominabili;
  - `Code Review & Test` solo quando richiesto dal lavoro;
  - `Doc Writer` ultimo step reale delle checklist multi-fase;
  - completed visibili ma mai riordinati fuori sequenza.
- Causa probabile:
  - policy di classificazione troppo superficiale;
  - sort locali duplicati in prompt/UI;
  - progression runtime che non considerava il primo item non terminale come gate della coda.
- Scope consentito:
  - `Tasking/Support` per classificazione e follow-up;
  - `TodoStore` per ordering/progression;
  - prompt runtime e formattazione `Current todos`;
  - test di regressione su runtime, prompt e pipeline.
- Non-scope:
  - redesign delle card;
  - refactor strutturale dei modelli todo;
  - cambi al workflow plan non necessari a questo bug.
- Moduli confinanti da verificare:
  - `TodoExecutionFollowUpPolicy`
  - `TodoStore+RuntimeExecutionProgression`
  - `TodoSummaryCardView`
  - `ChatPanelView+PartO_Streaming1`
  - `PipelineIntegrationService`
- Test da aggiungere o aggiornare:
  - espansione delle checklist monofase analitiche/implementative;
  - follow-up doc-only per checklist analitiche;
  - blocco dell’auto-advance su item precedenti `blocked`;
  - ordine del prompt `Current todos`;
  - visibilità persistente dei completed.
- Strategia di fix minimo:
  - introdurre classificazione esplicita delle fasi;
  - rimuovere i sort locali e usare la sequenza del runtime/store;
  - rendere il prossimo task promuovibile solo il primo non terminale della coda;
  - aggiornare il prompt per imporre fasi reali e non placeholder.
- Verifica post-fix:
  - suite XCTest mirata verde su policy, runtime progression, pipeline, prompt e overlay.
- Commit previsto:
  - `fix(todo): enforce real sequential todo phases`

## Bugs trovati

### P1 — La coda todo non era davvero sequenziale
- L’ordinamento runtime e alcune viste privilegiavano lo stato corrente invece della sequenza del lavoro.
- Fix: ordering condiviso e rimozione dei sort locali.

### P1 — Follow-up finali non modellati come fasi reali
- `Code Review & Test` era promosso da una policy troppo generica.
- Fix: classificazione esplicita delle fasi e gating condizionale review/doc.

### P1 — Task analitici multi-fase senza chiusura coerente
- Le checklist analitiche non producevano sempre una struttura finale consistente.
- Fix: espansione e follow-up `Doc Writer` per flow analitici reali.

### P2 — Prompt `Current todos` fuori ordine rispetto alla UI
- Il prompt rimandava i todo ordinati per stato, creando drift tra modello e superficie visibile.
- Fix: serializzazione del prompt nell’ordine del runtime.
