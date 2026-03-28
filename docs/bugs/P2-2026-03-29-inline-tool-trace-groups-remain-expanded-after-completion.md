# P2 - I gruppi trace inline restano espansi dopo il completamento

## Bug Fix Record
- Categoria: B - Importante
- Bug: i gruppi della trace inline in chat con chevron non si comprimevano quando l'attivita' era gia' conclusa.
- Sintomo: sezioni come `Esplorazione effettuata (...)` e `Modifiche applicate (...)` restavano aperte anche dopo la fine del task, lasciando la timeline lunga e meno leggibile.
- Impatto: peggiora l'ordine della chat e rende piu' costoso scansionare i messaggi completati.
- Gravita': P2
- Scope consentito: `App/SoloCodeApp/Sources/ChatView/Timeline/*`, test di regressione del trace inline e documentazione collegata.
- Non-scope: trace panel completo, artifact card, reducer timeline, flussi extra fuori dalla chat lineare.
- Expected result: un gruppo trace completato deve partire o tornare collassato automaticamente; l'espansione manuale dell'utente deve restare possibile.
- Rischi laterali: regressioni sul lifecycle del gruppo se un turno alterna eventi running/completed o se arrivano eventi con `isRunning` stale mentre `messageIsStreaming` e' gia' `false`.

## Priorita'

### 1) P2 - Mancava una policy di auto-collapse nel gruppo inline
- File:
  - `App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceViews.swift`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceGroupView.swift`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceGroupAutoPresentation.swift`
- Causa probabile:
  - la view inizializzava `isExpanded = true` e non riconciliava lo stato quando il gruppo smetteva di essere effettivamente running.
- Fix applicato:
  - introdotto helper di auto-presentation dedicato;
  - inizializzazione chiusa per gruppi gia' completati;
  - auto-collapse alla transizione running -> completed mantenendo la riapertura manuale disponibile.

### 2) P3 - File trace inline oltre la soglia di manutenzione
- File:
  - `App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceViews.swift`
- Sintomo:
  - il file accorpava event view, group view e row view, superando la soglia desiderata di manutenzione.
- Fix applicato:
  - estratta la view dei gruppi in file dedicati per confinare il fix e ridurre l'accoppiamento locale.
