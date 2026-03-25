# P0 — MCP SDK NetworkTransport.swift data race

**Date:** 2026-03-25
**Category:** A — Critico (blocca la build)
**Component:** Dipendenza esterna: `modelcontextprotocol/swift-sdk`
**Status:** Workaround applicato (package locale)

---

## Bug

MCP SDK (swift-sdk) versioni 0.8.0+ contiene due data race in `NetworkTransport.swift`
che diventano errori di compilazione con `swift-tools-version:6.0` (Swift 6 language mode).

## Sintomo

Clean build fallisce con 4 errori identici:
```
NetworkTransport.swift:532:33: error: sending 'sendContinuationResumed' risks causing data races
NetworkTransport.swift:763:29: error: sending 'receiveContinuationResumed' risks causing data races
```

## Impatto

Build completamente bloccata su clean build. Build incrementali funzionavano perche
i moduli SPM erano gia compilati nella cache.

## Causa

Due variabili locali (`sendContinuationResumed` e `receiveContinuationResumed`) sono
catturate in closure `@Sendable` ma non sono protette da isolation. In realta sono
accedute solo su `@MainActor`, ma il compilatore Swift 6 non puo provarlo staticamente.

## Workaround applicato

- Copiato MCP SDK 0.10.1 in `Packages/mcp-swift-sdk/` come package locale
- Applicato `nonisolated(unsafe)` sulle due variabili
- Rimosso riferimento remoto in `generate_xcode_project.rb`

## Soluzione permanente

Monitorare il repo upstream `modelcontextprotocol/swift-sdk` per un fix ufficiale.
Quando disponibile, rimuovere `Packages/mcp-swift-sdk/` e tornare al package remoto.

## Non-scope

Non usiamo `NetworkTransport` — solo `StdioTransport`. Il codice con data race non
viene mai eseguito nel nostro runtime.
