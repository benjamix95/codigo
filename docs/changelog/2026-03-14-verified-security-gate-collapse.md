# 2026-03-14 — Verified security gate collapse

## Modifiche
- rimosso [VerifiedFindingsSecurityGateService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSecurityGateService.swift)
- consolidati report, bridge e `evaluate(...)` in [SecurityWorkflowService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift)
- mantenuto uno shim compatibile `VerifiedFindingsSecurityGateService` nello stesso file
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- il nome pubblico usato dalla suite resta disponibile tramite shim compatibile

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSecurityGateService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
