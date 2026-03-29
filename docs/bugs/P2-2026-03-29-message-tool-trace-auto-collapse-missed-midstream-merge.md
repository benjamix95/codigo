# P2 - Message tool trace non si auto-collassa dopo il completamento di un evento intermedio

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la sezione tool/terminale nella chat poteva restare aperta anche dopo la fine del comando.
- Sintomo: l'utente vedeva il blocco trace ancora espanso o comunque non riallineato allo stato finale, lasciando la chat visivamente intasata.
- Impatto: degrado UX nella timeline chat; maggiore rumore visivo durante turni con più tool event e merge di `tool_finish`.
- Gravità: P2
- Steps to reproduce:
  1. Avviare un turno con almeno tre eventi trace.
  2. Far completare un evento terminale intermedio tramite merge del payload finale sullo stesso `toolUseId`.
  3. Lasciare invariato l'ultimo evento della lista.
  4. Osservare che la view del trace non invalida la cache derivata e non riesegue la logica di auto-compattazione.
- Risultato attuale: `MessageToolTraceView` osservava un token basato solo su primo/ultimo evento, quindi un cambio su un evento intermedio poteva non essere visto.
- Risultato atteso: qualsiasi mutazione rilevante di un evento del trace deve invalidare la cache derivata e consentire l'auto-collapse finale.
- Causa probabile: `eventsChangeToken` era troppo debole; ignorava cambiamenti di `isRunning`/`status` su eventi non in testa o in coda.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Views/MessageToolTrace/MessageToolTraceView+State.swift`
  - `Tests/SoloCodeAppTests/MessageToolTraceAutoPresentationTests.swift`
- Non-scope:
  - reducer timeline
  - store dei trace
  - layout grafico della card
- Moduli confinanti da verificare:
  - `MessageToolTraceView` cache derivata
  - auto-presentation del trace
- Test da aggiungere o aggiornare:
  - test di regressione sul token di invalidazione quando completa un evento intermedio
- Strategia di fix minimo: sostituire il token debole con un digest dell'intera collezione eventi, senza modificare il comportamento visuale o il collapser.
- Verifica post-fix:
  - test unitario sul `eventsChangeToken`
  - smoke test mirato della suite `MessageToolTraceAutoPresentationTests`
- Commit previsto: `fix(chat-trace): invalidate tool trace cache on midstream completion`
