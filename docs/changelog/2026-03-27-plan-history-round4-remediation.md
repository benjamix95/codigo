# Changelog

Data: 2026-03-27
Tipo: bugfix
Ambito: `PlanPanel`, `PlanHistoryStore`, `ChatStore` rewind/checkpoint

## Correzioni
- corretta la selection della plan history nei path `open/reset` del panel: ora il reset usa la conversazione corrente invece di una selection globale
- corretto il deep-link delle plan card in chat: `Open in Panel` e `Expand` salvano la selection nello scope del thread corrente
- resa esplicita la precedence preview `history scoped -> live board` quando il flow non richiede di preferire il live board
- corretto il rewind dei checkpoint: i linked plan board rimasti orfani vengono rimossi sia nel rewind a checkpoint sia nel rewind a message count

## Test
- aggiunti test di regressione su selection scoped per conversazione
- aggiunti test di regressione su cleanup dei linked plan board dopo rewind
- aggiunti test sul criterio di precedence del preview content tra history e live board

## Validazione
- eseguito `xcodebuild test` sui test mirati del sottosistema
- risultato: `22` test eseguiti, `0` failure
