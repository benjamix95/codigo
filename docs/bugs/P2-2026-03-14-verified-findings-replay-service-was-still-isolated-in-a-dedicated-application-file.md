# P2 - Il verified findings replay service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsReplayService.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo il report DTO e la logica di replay usata dal service verified findings.
- Sintomo: il replay di envelope/canonical snapshot viveva in un file standalone separato da `VerifiedFindingsService`.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsReplayService.swift`.
  2. Verificare che il file contenga solo `VerifiedFindingsReplayReport` e la logica di replay dell'envelope.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il replay service viveva in un file application dedicato.
- Risultato atteso: report e logica di replay devono stare in `VerifiedFindingsService.swift`, accanto alle altre API di risoluzione verified findings.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti, lasciando questo servizio residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - checkpoint service
  - UI panel
- Moduli confinanti da verificare:
  - `VerifiedFindingsReplayServiceTests`
  - `VerifiedFindingsServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente di replay e service riutilizzata
- Strategia di fix minimo:
  - spostare `VerifiedFindingsReplayReport` e le API `replay(...)` in `VerifiedFindingsService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/replay-service-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/replay-service-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/replay-service-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/replay-service-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/replay-service-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`
- Commit previsto: `refactor(review): fold replay service into verified findings service`

## Fix applicato
- `VerifiedFindingsReplayReport` e la logica di replay spostati in `VerifiedFindingsService.swift`
- rimosso `VerifiedFindingsReplayService.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
