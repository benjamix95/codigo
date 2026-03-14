# P1 - Il drenaggio del command coordinator rompeva la API pubblica lifecycle di BugHunter

## Bug Fix Record
- Categoria: A
- Bug: durante il drenaggio di `VerifiedFindingsCommandCoordinator.swift`, la API pubblica `BugHunterWorkflowService.queueLifecycleCommand(...)` non risultava più disponibile al target test/build.
- Sintomo: `BugHunterWorkflowServiceTests` falliva a compile-time con `type 'BugHunterWorkflowService' has no member 'queueLifecycleCommand'`.
- Impatto: il workflow BugHunter non era più compilabile in tutto il target `CoderEngineTests-Debug`.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`.
  2. Osservare l'errore sul file `BugHunterWorkflowServiceTests.swift`.
- Risultato attuale: la API pubblica non era più esposta.
- Risultato atteso: il simbolo `BugHunterWorkflowService.queueLifecycleCommand(...)` deve restare disponibile dopo il drenaggio del coordinator.
- Causa probabile: il method forwarding era rimasto nel file dedicato eliminato invece che in un file consolidato persistente.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/CodeReview`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI
  - runtime Rust
  - persistence
- Moduli confinanti da verificare:
  - `BugHunterWorkflowServiceTests`
  - `VerifiedFindingsStartCommandServiceTests`
  - `VerifiedFindingsCommandCoordinatorTests`
  - `CommandDeduplicationServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; la suite esistente copre già il contratto pubblico
- Strategia di fix minimo:
  - ripristinare `queueLifecycleCommand(...)` come extension di `BugHunterWorkflowService` in un file consolidato
  - completare il drenaggio di `VerifiedFindingsCommandCoordinator.swift`
- Verifica post-fix:
  - `validate_rust_cutover_boundary.sh`
  - `xcodebuild build-for-testing -scheme "CoderEngineTests-Debug"`
  - `xcodebuild test-without-building -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`
- Commit previsto: `refactor(review): fold command coordinator into verified services`
