# 2026-03-10 — MCP connect cleanup non bloccante

## Modifiche
- estratto `cleanupFailedConnection(process:resources:)` in `MCPTransportFactory`
- rimosso il `waitUntilExit()` dal path di cleanup quando `transport.connect()` fallisce
- mantenuto il rilascio immediato delle risorse del trasporto

## Test
- aggiunto `testCleanupFailedConnectionDoesNotWaitForProcessExit`

## Rischio controllato
- il processo viene comunque terminato
- il caller non resta più bloccato sul teardown
