# 2026-03-14 — Verified command coordinator collapse

## Modifiche
- rimosso [VerifiedFindingsCommandCoordinator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift)
- spostati `VerifiedCommandDeduplicationRecord` in [VerifiedFindingsCanonicalStore.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCanonicalStore.swift)
- spostati `VerifiedFindingsCommandError` e `VerifiedFindingsCommandOutcome` in [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift)
- spostati `VerifiedFindingsCommandCoordinator`, `EntityExecutionCoordinator` e `CommandDeduplicationService` in [VerifiedFindingsStartCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift)
- ripristinata la API pubblica `BugHunterWorkflowService.queueLifecycleCommand(...)` in [VerifiedFindingsLifecycleCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- il coordinator verified findings resta disponibile e testato dopo il drenaggio del file dedicato
- il contratto pubblico BugHunter per il queue lifecycle resta compatibile

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCanonicalStore.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
