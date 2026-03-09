# 2026-03-09 — VerifiedFindings service facade

## Obiettivo
Introdurre un facade condiviso `VerifiedFindingsService` che diventi l’entrypoint applicativo comune del core, invece di lasciare checkpoint/gate/replay composti manualmente dai chiamanti.

## Modifiche
- aggiunto `VerifiedFindingsService`
- aggiunto `VerifiedFindingsResolvedState`
- aggiornati a usare il facade:
  - `CodeReviewSessionSnapshot+VerifiedFindingsProjection`
  - `MCPSharedState+CodeReviewReads`
  - `SecurityHandler+Routing`
- aggiunti test di regressione per:
  - resolve da snapshot con envelope persistito
  - resolve da `sessionId` con rebuild dal canonical store

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Bridges/CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewReads.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests","-only-testing:CoderEngineTests/SecurityHandlerTests"]}'
```

Esito:
- 10 test eseguiti
- 0 failure

## Note
Questo non chiude ancora tutta la command API canonica del piano, ma finalmente fissa un entrypoint applicativo unico per i read path principali del core shared.
