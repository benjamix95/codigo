# 2026-03-10 — Session disposal MCP non bloccante

## Modifiche
- ripristinato il default `waitForExit: false` in `disposeSession(...)`
- centralizzata la terminazione del processo in `MCPTransportFactory.terminateProcess(...)`
- preservata la chiusura delle risorse del trasporto prima della terminate

## Test
- aggiunto `testResetSessionDoesNotWaitForProcessExit`

## Rischio controllato
- il lifecycle MCP non resta più serializzato dietro un server che ignora `SIGTERM`
