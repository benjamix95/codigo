# 2026-03-12 — Hardening MCP client contro `SIGPIPE`

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPTransportFactory.swift`
- il transport factory ora installa una sola volta `SIGPIPE -> SIG_IGN` prima di creare i pipe stdio dei subprocess MCP
- obiettivo:
  - evitare crash del processo chiamante quando un peer MCP chiude il pipe
  - convertire il failure in normale errore `EPIPE` gestibile dal runtime

## Validazione eseguita
- ispezione del failure xcresult del test `MCPSessionManagerTests.testCallToolRichRecordsMetrics()`
- verifica della causa sul path stdio subprocess
- rerun del test mirato prima che il runner `xcodebuild` entrasse in uno stato di signing non affidabile

## Esito
- il crash `signal pipe` viene trattato come problema di trasporto e non più come terminazione di processo
- resta aperto separatamente un problema del runner `xcodebuild` che può fallire a caricare il bundle test firmato
