# 2026-03-10 — Lifecycle MCP: cleanup selettivo non bloccante, restart espliciti sicuri

## Modifiche
- il teardown MCP è ora coordinato per `serverId`, così richieste concorrenti aspettano la fine del disconnect in-flight
- `session(for:)`, `resetSession`, `restartServer` ed eviction attendono un teardown attivo prima di proseguire
- `restartServer` e `reconnect` usano ora `waitForExit: true` per evitare processi sovrapposti
- i path passivi (`stale session`, eviction) restano non bloccanti sul `waitUntilExit`

## Test
- aggiunti:
  - `MCPSessionManagerTests/testRestartServerWaitsForPreviousProcessExitBeforeStartingReplacement`
  - `MCPSessionManagerTests/testConcurrentSessionRequestsWaitForInFlightTeardown`

## Rischio controllato
- nessun doppio bootstrap sullo stesso `serverId` mentre un teardown è ancora sospeso
- nessun restart esplicito che ritorna con il vecchio PID ancora vivo
- resta non bloccante il cleanup automatico di stale session ed eviction
