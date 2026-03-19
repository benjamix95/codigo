# P1 — i security audit già supportati dal core Rust venivano ancora eseguiti in Swift

## Categoria
- `A` critico

## Bug
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift) continuava a bypassare il core Rust per cinque tool security già implementati in [review_audit.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_audit.rs):
  - `audit_security_dataflow`
  - `audit_security_authz`
  - `audit_security_crypto`
  - `audit_security_deserialization`
  - `audit_security_surface`

## Sintomo
- Nel `switch` di `runTool(...)` questi tool passavano ancora da `runSecurity*Audit(...)` Swift invece che dal bridge `review_core_run_audit`.

## Impatto
- Ownership semantica ancora sdoppiata nel blocco audit.
- Rischio di drift fra output Rust e output Swift su finding, summary, metadata e verification hints.

## Gravità
- `P1`

## Steps to reproduce
1. Aprire [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift).
2. Cercare i case `securityDataflow`, `securityAuthz`, `securityCrypto`, `securityDeserialization`, `securitySurface`.
3. Prima del fix, osservare che chiamavano implementazioni locali Swift.

## Risultato attuale
- Prima del fix, questi security audit restavano owned dal service Swift anche se il core Rust li supportava già.

## Risultato atteso
- I tool security già supportati da Rust devono essere rust-first e fallire closed quando il runtime audit Rust non è disponibile.

## Causa probabile
- La migrazione audit si era fermata al bridge generico `default`, lasciando ancora alcuni case hardcoded nel service Swift.

## Scope consentito
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift)
- [CodeReviewAuditAdvancedTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift)
- `docs/bugs`
- `docs/changelog`

## Non-scope
- Tool audit ancora non supportati dal core Rust
- Meta-tool `audit_run_profile`, `audit_correlate_findings`, `audit_verify_bundle`, `audit_explain_finding`
- Provider core review

## Moduli confinanti da verificare
- `CodeReviewAuditAdvancedTests`
- i profile che includono i tool security audit

## Test da aggiungere o aggiornare
- test Rust-gated per `securityDataflow`
- test Rust-gated sui verification hints dei tool security rust-backed
- test fail-closed quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Strategia di fix minimo
- sostituire i cinque case security locali con il bridge Rust obbligatorio
- lasciare invariati i tool audit che Rust non implementa ancora

## Verifica post-fix
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`

## Commit previsto
- `refactor(review-audit): route rust-backed security tools through core`
