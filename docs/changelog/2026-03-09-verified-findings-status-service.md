# 2026-03-09 — VerifiedFindings status service

## Obiettivo
Centralizzare in un service shared la costruzione del payload di status `VerifiedFindings`, così MCP e superfici secondarie leggono gli stessi campi da un unico punto.

## Modifiche
- aggiunto `VerifiedFindingsStatusService`
- `MCPSharedState+CodeReviewReads` ora delega al service shared
- `BugHunterHandler+Reads` usa il service shared per lo status della review collegata
- aggiunto test di regressione in `VerifiedFindingsStatusServiceTests`

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewReads.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStatusServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests","-only-testing:CoderEngineTests/SecurityHandlerTests","-only-testing:CoderEngineTests/BugHunterHandlerTests"]}'
```

Esito:
- 12 test eseguiti
- 0 failure

## Note
Questo tranche completa la parte di status/read shared. Riduce ancora la dispersione di logica tra core, MCP e superfici `BugHunter`.
