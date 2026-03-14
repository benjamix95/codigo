# P2 - L'entity execution coordinator restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `EntityExecutionCoordinator.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo l'actor di serializzazione usato dal command coordinator.
- Sintomo: la mutua esclusione per `entityId` viveva in un file standalone separato dal coordinatore che la usa.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/EntityExecutionCoordinator.swift`.
  2. Verificare che il file contenga solo l'actor usato da `VerifiedFindingsCommandCoordinator`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il coordinatore di esclusione per entity viveva in un file application dedicato.
- Risultato atteso: l'actor deve stare in `VerifiedFindingsCommandCoordinator.swift`, accanto all'unico coordinatore che lo usa.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti, lasciando questo actor residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - MCP handler
  - UI panel
- Moduli confinanti da verificare:
  - `CommandDeduplicationServiceTests`
  - `VerifiedFindingsCommandCoordinator`
- Test da aggiungere o aggiornare:
  - `CommandDeduplicationServiceTests`
- Strategia di fix minimo:
  - spostare `EntityExecutionCoordinator` in `VerifiedFindingsCommandCoordinator.swift`
  - aggiungere una regression sulla serializzazione delle operazioni per lo stesso `entityId`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/entity-execution-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/entity-execution-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/entity-execution-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/entity-execution-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/entity-execution-source-packages" -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`
- Commit previsto: `refactor(review): fold entity execution into coordinator`

## Fix applicato
- `EntityExecutionCoordinator` spostato in `VerifiedFindingsCommandCoordinator.swift`
- aggiunta regression in `CommandDeduplicationServiceTests.swift`
- rimosso `EntityExecutionCoordinator.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
