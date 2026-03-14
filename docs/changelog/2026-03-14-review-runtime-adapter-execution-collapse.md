# 2026-03-14 — Review runtime adapter execution collapse

## Modifiche
- rimosso [ReviewRuntimeAdapter+Execution.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter+Execution.swift)
- consolidati i metodi execution in [ReviewRuntimeAdapter.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- il runtime adapter Rust pipeline resta invariato ma meno frammentato

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter.swift,Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter+Execution.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`

## Note
- questa tranche riduce il debito Swift non-UI del runtime review senza introdurre nuovi file
