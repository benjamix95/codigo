# [P1] Il client MCP poteva crashare con `SIGPIPE` scrivendo su un subprocess già chiuso

## Contesto
- test coinvolto: `MCPSessionManagerTests.testCallToolRichRecordsMetrics()`
- scenario: client MCP locale collegato via pipe stdio a un server subprocess

## Sintomo
- il test falliva in modo intermittente con:
  - `Test crashed with signal pipe.`

## Impatto
- crash del processo test invece di errore gestibile di trasporto
- instabilità nella suite MCP
- rischio teorico anche nel runtime app se un subprocess MCP chiude il pipe mentre il client sta ancora scrivendo

## Causa probabile
- su pipe POSIX, una write verso un peer già chiuso può generare `SIGPIPE`
- il path client MCP non mascherava esplicitamente il segnale, quindi un errore di trasporto poteva diventare un crash di processo

## Fix applicato
- installata una sola volta la policy `SIGPIPE -> SIG_IGN` in `MCPTransportFactory`
- risultato atteso:
  - la write fallita torna come `EPIPE`
  - il runtime gestisce il failure come errore di trasporto/retry invece di terminare il processo

## Verifica
- rerun del path mirato `MCPSessionManagerTests.testCallToolRichRecordsMetrics()`
- nessuna regressione sui test Rust del server MCP

## Stato
- risolto in questa tranche
