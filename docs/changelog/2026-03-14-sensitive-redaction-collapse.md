# 2026-03-14 — Sensitive redaction collapse

## Modifiche
- rimosso [SensitiveDataRedactionService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SensitiveDataRedactionService.swift)
- consolidato `SensitiveDataRedactionService` in [SecurityWorkflowService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservata la redaction di token, bearer, password e private key

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/sensitive-redaction-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/sensitive-redaction-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/sensitive-redaction-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/sensitive-redaction-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/sensitive-redaction-source-packages" -only-testing:CoderEngineTests/SensitiveDataRedactionServiceTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
