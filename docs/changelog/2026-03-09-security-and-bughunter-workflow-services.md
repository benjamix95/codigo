# 2026-03-09 — Security and BugHunter workflow services

## Obiettivo
Introdurre wrapper di dominio `Security` e `BugHunter` sopra il core shared `VerifiedFindings`, così gli handler MCP non compongono più direttamente query/gate/cluster/lifecycle.

## Modifiche
- aggiunto `SecurityWorkflowService`
- aggiunto `BugHunterWorkflowService`
- `SecurityHandler+Routing` ora usa i service shared per:
  - gate
  - findings
  - queue lifecycle
- `BugHunterHandler+Reads` ora usa i service shared per:
  - findings
  - cluster explanation
- `BugHunter` autofix app resta allineato al canonical shared state

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests","-only-testing:CoderEngineTests/SecurityHandlerTests","-only-testing:CoderEngineTests/BugHunterHandlerTests"]}'
```

Esito:
- 11 test eseguiti
- 0 failure

## Note
Questo tranche non rende ancora `Security` un motore completamente indipendente da review, ma crea finalmente wrapper di dominio first-class sopra il core shared.
