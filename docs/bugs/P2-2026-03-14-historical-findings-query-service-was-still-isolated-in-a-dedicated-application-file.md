# P2 - L'historical findings query service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `HistoricalFindingsQueryService.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo DTO query e read helpers coerenti con `VerifiedFindingsQueryService`.
- Sintomo: la query storica e lo shaping Rust dei record storici vivevano in un file separato dal query service verified findings.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/HistoricalFindingsQueryService.swift`.
  2. Verificare che il file contenga solo DTO e helper query storici.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il service query storico viveva in un file application dedicato.
- Risultato atteso: DTO e helper storici devono stare in `VerifiedFindingsQueryService.swift`, accanto al query service verified findings.
- Causa probabile: tranche precedenti avevano drenato helper review più urgenti, lasciando questo service residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - persistence schema
- Moduli confinanti da verificare:
  - `VerifiedFindingsQueryServiceTests`
  - `HistoricalFindingsQueryServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente delle query riutilizzata
- Strategia di fix minimo:
  - spostare DTO e helper storici in `VerifiedFindingsQueryService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/historical-query-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/historical-query-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/historical-query-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/historical-query-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/historical-query-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests`
- Commit previsto: `refactor(review): fold historical findings query into verified query service`

## Fix applicato
- `HistoricalFindingTimelineItem`, `HistoricalFindingRecord`, `HistoricalFindingsQuery` e gli helper storici spostati in `VerifiedFindingsQueryService.swift`
- rimosso `HistoricalFindingsQueryService.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
