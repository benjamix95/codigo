# Bug Fix Record — 2026-03-29 — Follow-up durante task attivo

## Bug Fix Record
- Categoria: B - Importante
- Bug: il composer del main chat non consentiva un follow-up ordinato mentre un task era in esecuzione; inoltre il submit da tastiera poteva aggirare il blocco UI e innescare un nuovo turn senza passare da un’interruzione esplicita del task corrente.
- Sintomo: per mandare un messaggio aggiuntivo durante l’esecuzione l’utente doveva premere stop, attendere la chiusura del task e poi reinviare; in parallelo `Enter` poteva comunque partire mentre `isLoading == true`, creando un percorso incoerente rispetto al pulsante invio nascosto.
- Impatto: UX frammentata, perdita di continuità del task, rischio di lifecycle sporco sul turno assistente precedente quando il nuovo invio avviene senza interrupt ordinato.
- Gravita': P1
- Steps to reproduce:
  1. Avvia un task nel main chat.
  2. Durante lo stream, scrivi un messaggio nel composer.
  3. Nota che il pulsante invio non e' disponibile; se usi `Enter`, il submit puo' comunque partire senza stop manuale.
- Risultato attuale: UI bloccata per il follow-up, ma submit tastiera non allineato alla stessa policy.
- Risultato atteso: l’utente deve poter inviare un follow-up durante il task attivo senza stop manuale; il sistema deve interrompere ordinatamente il task corrente e rilanciare subito il nuovo turn nello stesso thread.
- Causa probabile: la policy di invio era distribuita tra UI (`sendButton` nascosto/disabilitato su `isLoading`) e routing runtime (`handleComposerSend`/`sendMessage`) senza un unico punto di decisione. Il submit tastiera riusava `onSend` e non rispettava la stessa barriera visiva del composer.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatComposer/*`
  - `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/*`
  - `App/SoloCodeApp/Sources/ChatView/Composer/*`
  - `Tests/SoloCodeAppTests/*`
- Non-scope:
  - refactor dei provider/runtime transport
  - introduzione di un vero `send_input` live nel backend provider
  - modifiche al protocollo Rust/App Server
- Moduli confinanti da verificare:
  - composer send routing
  - runtime controls del composer
  - policy plan `awaitingChoice`
  - interrupt del task corrente
- Test da aggiungere o aggiornare:
  - regression test sulla route `idle` vs `task running`
  - regression test sul blocco submit in `awaitingChoice`
  - regression test sul requisito di context disponibile
- Strategia di fix minimo:
  - centralizzare la decisione di dispatch del composer in una policy piccola e testabile
  - esporre il bottone invio anche mentre il task e' attivo
  - far passare il submit del composer attivo da un helper che esegue `interruptTask(...)` seguito da `sendMessage()`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerSendPolicyTests`
- Commit previsto:
  - `fix(chat): allow direct follow-up sends during active tasks`

## Findings prioritizzati

### 1) P1 - Follow-up impossibile dal composer durante task attivo
- Il pulsante invio veniva disabilitato/nascosto quando `isLoading == true`, costringendo l’utente a interrompere manualmente il task.
- Fix: nuova policy `ComposerSendPolicy` e `runtimeControls` aggiornati per mostrare anche `sendButton` durante l’esecuzione.

### 2) P1 - Submit da tastiera non allineato alla policy UI
- `ComposerTextView` invocava `onSubmit` anche mentre il task era attivo, ma `handleComposerSend()` non trasformava il submit in un interrupt ordinato del task corrente.
- Fix: `handleComposerSend()` ora risolve esplicitamente la route `standardSend` vs `interruptAndSendFollowUp`; il follow-up attivo passa da `sendFollowUpDuringActiveTask()`.
