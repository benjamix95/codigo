# P1 — i bug audit già supportati dal core Rust cadevano ancora sul path Swift

## Categoria
- `A` critico

## Bug
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift) lasciava ancora i tool bug già supportati dal core Rust nel branch generico `default`, quindi senza enforcement rust-only:
  - `audit_bug_nil_crash_paths`
  - `audit_bug_test_impact`
  - `audit_bug_concurrency`

## Sintomo
- Questi tool non avevano più un case Swift dedicato, ma non erano nemmeno marcati come rust-only; in assenza del runtime audit Rust il service produceva ancora fallback generici invece di fail-closed esplicito.

## Impatto
- Ownership ancora ambigua su tre audit bug già implementati nel core Rust.
- Rischio di drift e di comportamento diverso in ambiente senza dylib Rust.

## Gravità
- `P1`

## Steps to reproduce
1. Aprire [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift).
2. Verificare che `audit_bug_nil_crash_paths`, `audit_bug_test_impact`, `audit_bug_concurrency` non fossero inclusi tra i tool rust-only.
3. Forzare `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1` ed eseguire uno di quei tool.

## Risultato attuale
- Prima del fix, i bug audit già rust-backed non avevano ancora fail-closed esplicito.

## Risultato atteso
- Devono essere trattati come i security audit rust-backed: runtime Rust obbligatorio, niente fallback semantico Swift.

## Causa probabile
- Il tranche precedente aveva chiuso solo i security audit già supportati dal core Rust.

## Scope consentito
- [CodeReviewAuditService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift)
- [CodeReviewAuditAdvancedTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift)
- `docs/bugs`
- `docs/changelog`

## Non-scope
- Tool bug audit ancora non supportati dal core Rust
- Meta-tool audit
- Provider core

## Moduli confinanti da verificare
- `CodeReviewAuditAdvancedTests`

## Test da aggiungere o aggiornare
- test Rust-gated su `bugNilCrashPaths`
- test Rust-gated su `bugTestImpact`
- regressione fail-closed per un bug audit rust-backed

## Strategia di fix minimo
- aggiungere i tre bug tool già supportati dal core Rust al blocco rust-only del service audit
- aggiornare i test audit per i nuovi path rust-backed

## Verifica post-fix
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`

## Commit previsto
- `refactor(review-audit): route rust-backed bug tools through core`
