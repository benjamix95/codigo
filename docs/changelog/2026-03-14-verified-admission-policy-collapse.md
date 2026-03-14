# 2026-03-14 — Verified admission policy collapse

## Modifiche
- rimosso [VerifiedFindingAdmissionPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingAdmissionPolicy.swift)
- consolidata `VerifiedFindingAdmissionPolicy` in [VerifiedFindingsStatusService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target

## Comportamento
- nessun cambiamento funzionale previsto
- preservate le regole di promozione e manual review dei verified findings

## Validazione eseguita
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/verified-admission-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/verified-admission-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/verified-admission-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/verified-admission-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/verified-admission-source-packages" -only-testing:CoderEngineTests/VerifiedFindingAdmissionPolicyTests`

## Note
- questa tranche riduce il debito Swift non-UI di `VerifiedFindingsCore` senza introdurre nuovi file
