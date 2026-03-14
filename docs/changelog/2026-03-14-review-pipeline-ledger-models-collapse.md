# 2026-03-14 — Review pipeline ledger models collapse

## Modifiche
- rimosso [ReviewPipelineLedgerModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/ReviewPipelineLedgerModels.swift)
- consolidati i modelli ledger in [CodeReviewSessionSnapshot+Derived.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionSnapshot+Derived.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)

## Comportamento
- nessun cambiamento funzionale previsto
- i ledger review restano invariati ma meno frammentati

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionSnapshot+Derived.swift,Engine/CoderEngine/Sources/CodeReview/Session/ReviewPipelineLedgerModels.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`

## Note
- questa tranche riduce il debito Swift non-UI review senza introdurre nuovi file
