# P1 — Mancava una copertura wire-level reale per `codex app-server` con MCP controllato

## Bug Fix Record
- Categoria: A — Critico
- Bug: la copertura esistente proteggeva parser, reducer, warmup e provisioning, ma non l'handshake reale `codex app-server` + MCP stub su wire JSON-RPC.
- Sintomo: una regressione nel transport esterno Codex poteva ancora passare le suite locali senza essere rilevata finché non rompeva il flusso reale.
- Impatto: rischio residuo su startup `ready/failed`, esposizione tool `coderide_*` e comportamento del bridge verso Codex CLI reale.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire solo test di parser/provisioning locali.
  2. Introdurre una regressione nel bootstrap MCP esterno di `codex app-server`.
  3. Osservare possibili suite verdi senza protezione wire-level.
- Risultato attuale: mancava una suite che lanciasse `codex app-server` reale con `CODEX_HOME` temporaneo e MCP stub controllato.
- Risultato atteso: avere test d'integrazione reali sul wire per entrambi i casi `coderide ready` e `coderide failed`.
- Causa probabile: gap di copertura fra test interni al provider e comportamento effettivo del processo esterno Codex.
- Scope consentito:
  - `Tests/CoderEngineTests/CodexAppServerMCPWireIntegrationTests.swift`
  - changelog e bug doc correlati
- Non-scope:
  - refactor del provider Codex
  - modifica del server MCP reale `coderide`
- Strategia di fix minimo:
  - lanciare `codex app-server` vero;
  - usare `CODEX_HOME` temporaneo con config MCP dedicata;
  - sostituire `coderide` con stub sano e stub guasto;
  - verificare `mcpServer/startupStatus/updated` e `mcpServerStatus/list`.
