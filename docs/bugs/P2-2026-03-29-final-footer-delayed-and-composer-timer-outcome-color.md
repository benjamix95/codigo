# [P2] Footer finale ritardato e timer composer senza esito semantico

## Bug Fix Record
- Categoria: B
- Bug: il footer `Task completed` non compare subito a fine task quando l'ultimo messaggio assistant resta con `isStreaming` stale; il timer del composer non distingue visivamente completamento riuscito e interruzione prematura del programma.
- Sintomo: il footer finale appare solo dopo riavvio app; il timer congelato usa sempre stile neutro.
- Impatto: bassa affidabilità percepita della chiusura task e stato finale poco leggibile nel composer.
- Gravità: media
- Steps to reproduce:
  1. Completare un task e osservare che il footer finale non compare.
  2. Riavviare l'app e osservare che il footer appare.
  3. Terminare task con esiti diversi e osservare il timer composer con stile invariato.
- Risultato attuale: footer bloccato da `isStreaming` stale; timer finale senza differenza success/error.
- Risultato atteso: footer visibile subito quando il messaggio assistant è terminale anche se il bit streaming è stale; timer verde su successo, rosso su interruzione/errore programma.
- Causa probabile: decisione UI del footer troppo rigida su `lastMessage.isStreaming`; stato congelato del timer basato solo su `endedByManualStop`.
- Scope consentito: helper `shouldShowFinalChatActions`, stato/runtime timer composer, propagation outcome task.
- Non-scope: layout footer, ordering timeline, sidebar, subagent cards.
- Moduli confinanti da verificare: lifecycle del composer, tool trace turn finalization, tests footer final actions.
- Test da aggiungere o aggiornare: regressioni su footer con streaming stale e tone del timer composer.
- Strategia di fix minimo: rendere terminale il footer su turn metadata completata/fallita/cancellata; propagare `ToolTraceTurnOutcome` al timer congelato.
- Verifica post-fix: test unitari mirati su footer e timer.
- Commit previsto: `fix(chat): show final footer immediately and color composer timer`
