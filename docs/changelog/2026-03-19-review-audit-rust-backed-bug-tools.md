# 2026-03-19 — Review audit bug tools rust-backed

## Modifiche
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift) tratta ora come rust-only anche i bug audit già supportati dal core Rust:
  - `audit_bug_nil_crash_paths`
  - `audit_bug_test_impact`
  - `audit_bug_concurrency`
- aggiornata [CodeReviewAuditAdvancedTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift) con test Rust-gated e regressione fail-closed

## Motivazione
- completare il sottoinsieme dei tool audit già implementati nel core Rust, senza lasciare metà security e metà bug ancora con policy diverse

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`
