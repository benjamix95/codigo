# 2026-03-16 - Review MCP host zero e diff summary in Rust

## Tranche completata
- migrato il diff summary review in Rust:
  - `Native/RustCore/src/review_diff/mod.rs`
  - `Native/RustCore/src/review_diff/git.rs`
  - `Native/RustCore/src/ffi/review_diff.rs`
- rimosso il servizio Swift legacy:
  - `Engine/CoderEngine/Sources/CodeReview/Services/ReviewDiffSummaryService.swift`
- aggiunto il bridge Swift minimale:
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/ReviewDiffSummaryRustBridge.swift`
- ricollocati i file host MCP review fuori dal prefisso hard-fail:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewHandler+Findings.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewHandler+PatchWorkflow.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewHandler+Start.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/CodeReviewRustHandlerSupport.swift`
- aggiornati test e project:
  - `Tests/CoderEngineTests/CodeReview/ReviewDiffSummaryServiceTests.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewCandidateVerificationServiceTests.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewCoreTestSupport.swift`
  - `Solo Code.xcodeproj/project.pbxproj`

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_diff`
- `cargo build --manifest-path Native/RustCore/Cargo.toml --lib`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewDiffSummaryServiceTests -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests -only-testing:CoderEngineTests/CodeReviewHandlerTests`
- audit strict review-scope:
  - prima: `47` legacy non-UI
  - dopo: `42` legacy non-UI

## Note
- il prefisso `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview` e' ora a zero file legacy
- il debito review residuo e' rimasto solo in:
  - `Engine/CoderEngine/Sources/CodeReview`: `28`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `14`
- `xcodebuildmcp` non e' esposto in questo ambiente; per questa tranche la validazione Apple e' stata eseguita con `xcodebuild` diretto
