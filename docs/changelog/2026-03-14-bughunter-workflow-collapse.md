# 2026-03-14 — BugHunter workflow collapse

## Modifiche
- rimosso [BugHunterWorkflowService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift)
- mantenuto il simbolo `BugHunterWorkflowService` distribuendo le API in:
  - [BugHunterAutofixSelectionService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift)
  - [VerifiedFindingsStartCommandService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift)
  - [VerifiedFindingsCommandCoordinator.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- il workflow BugHunter resta invariato ma meno frammentato

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
