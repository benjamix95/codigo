# P1 — Il command loop review poteva segnare `completed` prima della snapshot finale persistita

## Categoria
Categoria A

## Bug
Nel path deferred del code review command loop, il comando poteva essere marcato `completed` prima che la snapshot finale `.completed` fosse sicuramente scritta nello shared state.

## Sintomo
Test e runtime potevano osservare:
- comando `completed`
- session snapshot ancora in fase `analyzing`

## Impatto
Race di stato tra command bus e source of truth della sessione review, con rischio di UI incoerente e polling che legge stato terminale incompleto.

## Gravità
Alta

## Causa probabile
La persistenza della snapshot finale passava dal callback `onStateChange` asincrono, mentre il command veniva chiuso subito dopo il termine dello stream provider.

## Fix applicato
- persistenza esplicita della live review state prima di marcare il comando come `completed`
- riduzione della race tra transport state e review snapshot state

## Regressione da coprire
- deferred review start: command `completed` solo quando la snapshot è davvero `.completed`
