# 2026-03-19 — Review audit security tools rust-backed

## Modifiche
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift) instrada ora i cinque security audit già supportati dal core Rust attraverso il bridge obbligatorio:
  - `audit_security_dataflow`
  - `audit_security_authz`
  - `audit_security_crypto`
  - `audit_security_deserialization`
  - `audit_security_surface`
- aggiunto fail-closed con summary esplicito quando il runtime audit Rust non è disponibile
- aggiornata la suite [CodeReviewAuditAdvancedTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift) con helper Rust-gated e regressione fail-closed

## Motivazione
- ridurre il backlog finale nel blocco audit spostando ownership reale verso Rust sui tool già implementati dal core

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`

## Note
- I tool audit non ancora implementati nel core Rust restano fuori scope in questo batch e continuano a usare il path Swift esistente.
