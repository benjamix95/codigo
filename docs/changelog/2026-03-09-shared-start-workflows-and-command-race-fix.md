# 2026-03-09 — Shared start workflows and command race fix

## Obiettivo
Completare il passaggio dello start workflow sotto servizi shared di dominio e chiudere la race tra completamento del command review e persistenza della snapshot finale.

## Modifiche
- `SecurityWorkflowService` ora costruisce il request di start condiviso
- `BugHunterWorkflowService` ora costruisce il request di start review collegato alla run
- `SecurityHandler+Routing` usa il workflow service shared per `security_start`
- `CodigoApp+BugHunterExecution` usa il workflow service shared per il review-start di `BugHunter`
- `CodigoApp+CodeReviewDeferredCommands` ora persiste la live review state finale prima di marcare il command come `completed`
- aggiunti test unitari sul building dei request di start in `VerifiedFindingsStartCommandServiceTests`

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/BugHunter/CodigoApp+BugHunterExecution.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/CodigoApp+CodeReviewDeferredCommands.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests","-only-testing:CoderEngineTests/CodeReviewHandlerTests","-only-testing:CoderEngineTests/SecurityHandlerTests","-only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests"]}'
```

Esito:
- 58 test eseguiti
- 0 failure

## Note
Questo tranche porta ancora più start logic sul core shared e chiude una race concreta nel command loop review.
