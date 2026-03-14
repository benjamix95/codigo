# P2 - Il checkpoint service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsCheckpointService.swift` restava un file Swift non-UI separato pur contenendo solo recovery helpers del dominio verified findings.
- Sintomo: il dominio `VerifiedFindingsCore` manteneva un file legacy dedicato per `resolveEnvelope` e `rebuildEnvelope`.
- Impatto: un file Swift non-UI in piu' nel dominio review e ownership distribuita tra service e checkpoint helpers.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCheckpointService.swift`.
  2. Verificare che il file contenga solo recovery helpers e DTO `RecoveredEnvelope`.
  3. Notare che il file compare nel backlog `VerifiedFindingsCore`.
- Risultato attuale: i recovery helpers vivevano in un file dedicato.
- Risultato atteso: i DTO recovery devono stare in `VerifiedFindingsService.swift` e il service di checkpoint in `VerifiedFindingsStatusService.swift`, senza file separato.
- Causa probabile: tranche precedenti avevano drenato services verified findings più urgenti lasciando questo file residuale isolato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - panel UI
  - persistence schema
  - runtime Rust
- Moduli confinanti da verificare:
  - `VerifiedFindingsReplayServiceTests`
  - `VerifiedFindingsService`
  - `VerifiedFindingsStatusService`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso della suite replay/checkpoint già esistente
- Strategia di fix minimo:
  - spostare `VerifiedFindingsEnvelopeSource` e `VerifiedFindingsRecoveredEnvelope` in `VerifiedFindingsService.swift`
  - spostare `VerifiedFindingsCheckpointService` in `VerifiedFindingsStatusService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCheckpointService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`
- Commit previsto: `refactor(review): fold checkpoint recovery into verified services`

## Fix applicato
- `VerifiedFindingsEnvelopeSource` e `VerifiedFindingsRecoveredEnvelope` spostati in `VerifiedFindingsService.swift`
- `VerifiedFindingsCheckpointService` spostato in `VerifiedFindingsStatusService.swift`
- rimosso `VerifiedFindingsCheckpointService.swift` dal filesystem e dal progetto Xcode

## Esito
- `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
