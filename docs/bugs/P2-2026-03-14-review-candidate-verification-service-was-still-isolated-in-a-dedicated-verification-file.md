# P2 - Il candidate verification service restava isolato in un file verification dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewCandidateVerificationService.swift` restava un file Swift non-UI separato pur definendo solo il service e i payload usati dal coordinator review.
- Sintomo: il dominio `CodeReview` manteneva un file legacy dedicato nella cartella `Verification` senza ownership autonoma.
- Impatto: un file Swift non-UI in piu' nel dominio review e frammentazione inutile del flow di candidate verification.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift`.
  2. Verificare che il file contenga solo `ReviewCandidateVerificationService`, il result type e i payload FFI.
  3. Notare che il file compare ancora nel backlog Swift del dominio review.
- Risultato attuale: il service di verification viveva in un file dedicato.
- Risultato atteso: il service deve stare accanto al coordinator review che lo usa, in `ReviewPipelineCoordinator+CandidateVerification.swift`.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti lasciando questo service residuale separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline`
  - `Engine/CoderEngine/Sources/CodeReview/Verification`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI
  - persistence
- Moduli confinanti da verificare:
  - `ReviewCandidateVerificationServiceTests`
  - `ReviewPipelineCoordinator`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso della suite esistente di candidate verification
- Strategia di fix minimo:
  - spostare service, result type e payload FFI nel file del coordinator candidate verification
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift,Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests`
- Commit previsto: `refactor(review): fold candidate verification into pipeline coordinator`

## Fix applicato
- `ReviewCandidateVerificationService`, `ReviewCandidateVerificationResult` e i payload FFI sono stati spostati in `ReviewPipelineCoordinator+CandidateVerification.swift`
- rimosso `ReviewCandidateVerificationService.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `CodeReview` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
