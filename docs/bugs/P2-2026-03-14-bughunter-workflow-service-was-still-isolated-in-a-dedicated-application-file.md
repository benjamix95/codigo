# P2 - Il BugHunter workflow service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `BugHunterWorkflowService.swift` restava un file Swift non-UI separato pur esponendo solo API distribuite tra autofix selection, start request, query e queue lifecycle.
- Sintomo: il dominio `VerifiedFindingsCore` manteneva un file legacy dedicato con responsabilita' già coperte da altri service adiacenti.
- Impatto: backlog Swift non-UI più alto e ownership frammentata del workflow BugHunter.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift`.
  2. Verificare che il file contenga solo `makeStartRequest`, `findings`, `selectAutofixFindingId`, `explainCluster` e `queueLifecycleCommand`.
  3. Notare che il file compare ancora nel backlog hard-fail di `VerifiedFindingsCore`.
- Risultato attuale: il workflow BugHunter viveva in un file separato.
- Risultato atteso: il simbolo pubblico `BugHunterWorkflowService` deve restare, ma le sue API devono essere distribuite in file già owner delle rispettive responsabilità.
- Causa probabile: tranche precedenti avevano drenato service verified findings più urgenti lasciando questo wrapper di workflow residuo.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI panel
  - runtime Rust
  - persistence schema
- Moduli confinanti da verificare:
  - `BugHunterWorkflowServiceTests`
  - `VerifiedFindingsStartCommandServiceTests`
  - `VerifiedFindingsCommandCoordinatorTests`
  - `CommandDeduplicationServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso delle suite esistenti
- Strategia di fix minimo:
  - definire il simbolo `BugHunterWorkflowService` in un file già esistente
  - spostare:
    - cluster/autofix in `BugHunterAutofixSelectionService.swift`
    - `makeStartRequest` in `VerifiedFindingsStartCommandService.swift`
    - `findings` in `BugHunterAutofixSelectionService.swift`
    - `queueLifecycleCommand` in `VerifiedFindingsCommandCoordinator.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCommandCoordinator.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`
- Commit previsto: `refactor(review): fold bughunter workflow into verified services`

## Fix applicato
- `BugHunterWorkflowService` resta disponibile come simbolo pubblico, ma le sue API sono state redistribuite su:
  - `BugHunterAutofixSelectionService.swift`
  - `VerifiedFindingsStartCommandService.swift`
  - `VerifiedFindingsCommandCoordinator.swift`
- rimosso `BugHunterWorkflowService.swift` dal filesystem e dal progetto Xcode

## Esito
- `VerifiedFindingsCore` riduce di una ulteriore unità il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
