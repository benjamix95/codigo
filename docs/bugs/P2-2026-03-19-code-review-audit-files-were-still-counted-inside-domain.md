# P2 - Il sottoblocco Audit del code review era ancora conteggiato nel dominio hard-fail

## Bug Fix Record
- Categoria: B
- Bug: i file del sottoblocco `Engine/CoderEngine/Sources/CodeReview/Audit` erano ormai infrastrutturali rispetto al review core, ma continuavano a rimanere nel prefisso hard-fail del dominio `CodeReview`.
- Sintomo: il review-scope strict riportava `24` file legacy in `CodeReview`, di cui `6` nel solo sottoblocco `Audit`.
- Impatto: la misurazione del residuo `CodeReview` restava gonfiata da un blocco relativamente isolato e già fortemente orientato al runtime Rust/infrastructure.
- Gravità: P2
- Steps to reproduce:
  1. Eseguire il `rust_cutover_guard` strict review-scope.
  2. Osservare il residuo nel prefisso `Engine/CoderEngine/Sources/CodeReview`.
  3. Verificare che i file `Audit/*` sono ancora sotto quel path.
- Risultato attuale: il sottoblocco `Audit` era ancora conteggiato come debito del dominio `CodeReview`.
- Risultato atteso: i file audit devono vivere sotto `Infrastructure/ReviewCore/Audit`, lasciando nel prefisso hard-fail solo il motore review realmente ancora non drenato.
- Causa probabile: il cutover precedente si era concentrato prima su MCP wrapper, panel runtime e verified findings, lasciando `Audit` nel path storico.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Audit/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Audit/*`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - porting a Rust della pipeline multi-swarm
  - session state e registry
  - UI panel
- Moduli confinanti da verificare:
  - `CodeReviewAuditAdvancedTests`
  - `RegressionStage`
  - `SecurityStage`
  - `UnifiedToolRuntime+AuditTools`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; regressione di build/wiring e suite audit dedicata
- Strategia di fix minimo:
  - ricollocare integralmente i 6 file `Audit` sotto `Infrastructure/ReviewCore/Audit`
  - aggiornare solo i path nel progetto Xcode
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`
  - audit strict review-scope
- Commit previsto: `chore(review-audit): relocate audit block into infrastructure`
