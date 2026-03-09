# 2026-03-09 — Security gate enforced on start

## Obiettivo
Trasformare il gate quantitativo `Security` da semplice metrica informativa a blocco operativo reale sul tool MCP `security_start`.

## Modifiche
- `SecurityHandler+Routing` ora:
  - valuta il gate corrente dai snapshot `VerifiedFindings`
  - blocca `security_start` quando il gate non è pronto
  - arricchisce `security_status` con `security_gate_ready` e `security_gate_summary` anche senza sessione attiva
- aggiunti test MCP per:
  - start consentito con gate ready
  - start bloccato senza baseline
  - status con summary gate senza sessione

## File toccati
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `Tests/CoderEngineTests/Security/SecurityHandlerTests.swift`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/SecurityHandlerTests"]}'
```

Esito:
- 6 test eseguiti
- 0 failure

## Note
Questo tranche non introduce una pipeline `Security` separata. Rende però coerente l’enforcement del gate quantitativo sul backend shared già esistente.
