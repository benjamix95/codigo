# P2 - I projection models dei verified findings restavano isolati in un file dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsProjectionModels.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore/Projection` pur contenendo solo i DTO usati dal builder della projection.
- Sintomo: `VerifiedFindingListItemProjection` e `VerifiedFindingsProjectionSnapshot` vivevano in un file separato dal builder che li costruisce.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection/VerifiedFindingsProjectionModels.swift`.
  2. Verificare che il file contenga solo DTO della projection builder.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: i projection models vivevano in un file dedicato.
- Risultato atteso: i DTO devono stare in `VerifiedFindingsProjectionBuilder.swift`, accanto al builder che li materializza.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti, lasciando questi DTO residuali in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - application services
  - UI panel
- Moduli confinanti da verificare:
  - `VerifiedFindingsProjectionBuilderTests`
  - `VerifiedFindingsStatusServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente della projection riutilizzata
- Strategia di fix minimo:
  - spostare `VerifiedFindingListItemProjection` e `VerifiedFindingsProjectionSnapshot` in `VerifiedFindingsProjectionBuilder.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/projection-models-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/projection-models-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/projection-models-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/projection-models-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/projection-models-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests`
- Commit previsto: `refactor(review): fold projection models into projection builder`

## Fix applicato
- `VerifiedFindingListItemProjection` e `VerifiedFindingsProjectionSnapshot` spostati in `VerifiedFindingsProjectionBuilder.swift`
- rimosso `VerifiedFindingsProjectionModels.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
