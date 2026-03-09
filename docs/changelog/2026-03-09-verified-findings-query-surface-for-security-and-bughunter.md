# 2026-03-09 — VerifiedFindings query surface for Security and BugHunter

## Obiettivo
Portare i list/read path di `Security` e `BugHunter` sul query layer shared `VerifiedFindings`, riducendo ancora la dipendenza residua dal modello review legacy.

## Modifiche
- aggiunto `VerifiedFindingsQueryService`
- il modello canonico `VerifiedFinding` ora conserva anche `sourceOrigin`
- `VerifiedFindingsSessionSyncService` popola e preserva `sourceOrigin`
- `readCodeReviewFindings` delega al query layer shared
- `security_findings` usa direttamente `VerifiedFindingsQueryService`
- `bughunter_findings` usa direttamente `VerifiedFindingsQueryService`
- aggiunti test di regressione in:
  - `VerifiedFindingsQueryServiceTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingModels.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService+Mappings.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewReads.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsQueryServiceTests.swift`
- `Tests/CoderEngineTests/Security/SecurityHandlerTests.swift`
- `Tests/CoderEngineTests/BugHunter/BugHunterHandlerTests.swift`
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
Questo tranche non elimina ancora tutta la compat layer review, ma completa un pezzo importante: i comandi list/read principali di `Security` e `BugHunter` passano finalmente dal query layer shared del core.
