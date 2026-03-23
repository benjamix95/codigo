# 2026-03-09 — VerifiedFindings start command service

## Obiettivo
Portare anche l’avvio della review dietro una surface shared del core, così `review_start` e `bughunter_start` usano la stessa validazione e la stessa queue.

## Modifiche
- aggiunto `VerifiedFindingsStartCommandService`
- `CodeReviewHandler+Start` ora delega al service shared
- `SoloCodeApp+BugHunterExecution` usa il service shared per accodare il review start collegato alla run
- `VerifiedFindingsQueryService` riallineato alla redazione storica di `review_findings`
- aggiunti test di regressione in `VerifiedFindingsStartCommandServiceTests`

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/BugHunter/SoloCodeApp+BugHunterExecution.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests","-only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests","-only-testing:CoderEngineTests/CodeReviewHandlerTests","-only-testing:CoderEngineTests/SecurityHandlerTests","-only-testing:CoderEngineTests/BugHunterHandlerTests"]}'
```

Esito:
- 58 test eseguiti
- 0 failure

## Note
Questo tranche non chiude ancora tutta l’orchestrazione start dei domini, ma finalmente unifica il punto di ingresso più importante del workflow shared.
