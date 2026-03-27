# Changelog

Data: 2026-03-27
Tipo: analisi
Ambito: `PlanPanel`, `PlanHistoryStore`, `ChatStorePlans`, `startup/bootstrap`

## Aggiunto
- nuovo report di deep analysis round 5 sui bug residui del flusso plan/history/live-board

## Finding principali registrati
- `Build` usa ancora il live board anche quando il panel mostra una history entry selezionata
- `planBoardDidPersist` può aggiornare la history entry sbagliata nelle conversazioni con più snapshot
- la history list permette selezioni cross-thread-root compatibili che il resolver poi invalida quando manca un context esplicito
- il bootstrap attachment/history muta in background la selection utente
- la deduplica del backfill legacy non copre davvero i casi senza `sourceMessageId`
- il sync `planBoard -> history` resta parziale anche quando colpisce l’entry giusta
