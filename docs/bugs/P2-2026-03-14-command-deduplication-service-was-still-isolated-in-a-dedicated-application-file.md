# P2 - Il command deduplication service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CommandDeduplicationService.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo record e actor strettamente usati dal command coordinator.
- Sintomo: il servizio di deduplica command viveva in un file standalone separato dal coordinatore che lo possiede.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/CommandDeduplicationService.swift`.
  2. Verificare che il file contenga solo il record e l'actor usato da `VerifiedFindingsCommandCoordinator`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il servizio di deduplica command viveva in un file application dedicato.
- Risultato atteso: record e actor devono stare in `VerifiedFindingsCommandCoordinator.swift`, accanto all'unico coordinatore che li usa.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti, lasciando questo servizio residuale in un file separato.
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
  - nessun nuovo test: copertura esistente della deduplica riutilizzata
- Strategia di fix minimo:
  - spostare `VerifiedCommandDeduplicationRecord` e `CommandDeduplicationService` in `VerifiedFindingsCommandCoordinator.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/command-dedup-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/command-dedup-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/command-dedup-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/command-dedup-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/command-dedup-source-packages" -only-testing:CoderEngineTests/CommandDeduplicationServiceTests`
- Commit previsto: `refactor(review): fold command deduplication into coordinator`

## Fix applicato
- `VerifiedCommandDeduplicationRecord` e `CommandDeduplicationService` spostati in `VerifiedFindingsCommandCoordinator.swift`
- rimosso `CommandDeduplicationService.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
