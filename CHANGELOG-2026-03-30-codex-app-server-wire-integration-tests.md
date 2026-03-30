# Changelog — 2026-03-30 — Codex app-server wire integration tests

## Cosa ho aggiunto

- Nuova suite reale: [CodexAppServerMCPWireIntegrationTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodexAppServerMCPWireIntegrationTests.swift)
- La suite lancia:
  - `codex app-server` reale
  - `CODEX_HOME` temporaneo
  - auth Copiata dal profilo utente, quando disponibile
  - due stub MCP controllati:
    - stub sano che risponde a `initialize` e `tools/list`
    - stub guasto che chiude il canale durante l'handshake

## Contratti blindati

### Caso sano
- `coderide` deve entrare in `ready`
- `mcpServerStatus/list` deve esporre tool `coderide_*`
- il wire reale non deve restituire un catalogo vuoto

### Caso guasto
- `coderide` deve entrare in `failed`
- l'errore deve includere il fallimento di handshake/initialize
- il catalogo tool di `coderide` deve restare vuoto

## Perché serve

Questa suite chiude il gap rimasto tra:
- test locali di parser/provisioning
- comportamento reale del processo esterno `codex app-server`

In pratica, se il wire MCP di Codex si rompe di nuovo, adesso abbiamo una guardia che lo vede sul processo reale, non solo sui layer interni.
