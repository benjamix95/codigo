# 2026-03-09 — VerifiedFindings checkpoint and replay services

## Obiettivo
Estrarre un piccolo service layer condiviso per il recupero da checkpoint e per il replay del projection model `VerifiedFindings`, così da togliere logica sparsa da bridge e read path.

## Modifiche
- aggiunto `VerifiedFindingsCheckpointService`
- aggiunto `VerifiedFindingsReplayService`
- il bridge `CodeReviewSessionSnapshot+VerifiedFindingsProjection` ora usa il service condiviso per risolvere l’envelope
- `readCodeReviewStatus` espone anche metadati di:
  - source dell’envelope
  - checkpoint persistito
  - replay del projection model
- aggiunti test di regressione per:
  - envelope recovery preferendo lo storage
  - rebuild da canonical snapshot
  - replay summary coerente

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCheckpointService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsReplayService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Bridges/CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewReads.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsReplayServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests","-only-testing:CoderEngineTests/SecurityHandlerTests"]}'
```

Esito:
- 8 test eseguiti
- 0 failure

## Note
Questo tranche non introduce event sourcing completo. Chiude però il layer applicativo minimo richiesto per `checkpoint/rebuild/replay summary` del core shared.
