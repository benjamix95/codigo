# 2026-03-14 — Review MCP handler Rust boundary hardening

## Modifiche
- rimosso [CodeReviewHandler.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler.swift)
- consolidata la surface di routing review MCP in [CodeReviewHandler+Start.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift)
- consolidati i fallback findings/filter in [CodeReviewHandler+Findings.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Findings.swift)
- harden del boundary Rust in [CodeReviewRustHandlerSupport.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewRustHandlerSupport.swift)
- fallback queue/apply patch in [CodeReviewHandler+PatchWorkflow.swift](/Users/benjaminstoica/SoloCode/Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift)
- regression aggiunte in [CodeReviewHandlerTests+Validation.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+Validation.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il wrapper file legacy

## Comportamento
- `review_start` non richiede piu' una sessione preesistente e preserva il contratto locale dei messaggi di errore/queue
- i tool MCP review read-only e patch lifecycle non falliscono piu' con `Rust review core unavailable` quando il bridge Rust restituisce `nil`
- il boundary review mantiene il comportamento atteso anche con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Validazione eseguita
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Findings.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewRustHandlerSupport.swift,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift,Tests/CoderEngineTests/CodeReview/CodeReviewHandlerTests+Validation.swift,Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
- `./scripts/bootstrap_test_bundles.sh`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`

## Note
- questa tranche chiude il blocco del handler MCP review senza introdurre nuovi file Swift non-UI
- il prefisso hard-fail review MCP scende da `6` a `5` file Swift legacy
