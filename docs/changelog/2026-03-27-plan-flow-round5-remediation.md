# Changelog

Data: 2026-03-27
Tipo: bugfix
Ambito: `PlanPanel`, `PlanHistoryStore`, `ChatStorePlans`

## Correzioni
- allineata la precedence tra preview/download/build del `PlanPanel`: quando il flow non richiede il live board, il build usa davvero la history entry selezionata
- corretta la compatibilità history nei thread senza context esplicito, così la selection di entry sorelle nello stesso thread root non viene più scartata
- corretto il sync `planBoardDidPersist`: ora aggiorna l’entry attiva o più recente della conversazione e sincronizza anche `title`, `options` e `chosenPath`
- corretto il bootstrap/backfill degli attachment plan: riusa entry legacy con `sourceMessageId` mancante tramite hash e non muta più la selection utente

## Test
- aggiunti test sulla precedence del build choice
- aggiunti test sulla compatibilità history cross-thread senza context
- aggiunti test multi-entry per `planBoardDidPersist`
- aggiunto test bootstrap/backfill legacy senza side effect di selection

## Validazione
- eseguito `xcodebuild test` sui test mirati del sottosistema
- risultato: `42` test eseguiti, `0` failure
