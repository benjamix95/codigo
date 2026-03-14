# P2 - La correlation audit restava isolata in un file audit dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewAuditService+Correlation.swift` restava un file Swift non-UI separato pur contenendo solo `correlateFindings`, `runProfile` e `correlateResults`.
- Sintomo: il dominio `CodeReview` manteneva un file residuale di puro supporto audit.
- Impatto: backlog Swift non-UI più alto e ownership frammentata dell'audit service.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Correlation.swift`.
  2. Verificare che il file contenga solo helper di correlation/profile.
  3. Notare che il file compare ancora nel backlog hard-fail `CodeReview`.
- Risultato attuale: gli helper correlation/profile vivevano in un file separato.
- Risultato atteso: gli helper devono stare in `CodeReviewAuditService+Support.swift`, accanto agli altri support helper dell'audit service.
- Causa probabile: tranche precedenti avevano drenato file review più urgenti lasciando questo helper file residuale.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Audit`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - panel UI
  - runtime Rust
  - verified findings
- Moduli confinanti da verificare:
  - `CodeReviewAuditAdvancedTests` subset correlation
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso del subset esistente
- Strategia di fix minimo:
  - spostare correlation/profile helpers in `CodeReviewAuditService+Support.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `validate_rust_cutover_boundary.sh`
  - `xcodebuild build-for-testing -scheme "CoderEngineTests-Debug"`
  - `xcodebuild test-without-building -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testCorrelateResultsBuildsClusters -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testRunProfileSecurityDeepIncludesAdvancedSecurityTools -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests/testVerificationHintsContainNoEmptyStrings`
- Commit previsto: `refactor(review): fold audit correlation into support`
