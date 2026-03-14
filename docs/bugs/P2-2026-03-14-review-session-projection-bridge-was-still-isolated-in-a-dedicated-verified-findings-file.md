# P2 - Il bridge di projection del review session snapshot restava isolato in un file dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift` restava un file Swift non-UI dedicato pur contenendo solo due computed property di inoltro verso `VerifiedFindingsService`.
- Sintomo: `verifiedFindingsProjection` e `canonicalVerifiedFindingsSnapshot` vivevano in un bridge separato dal resto dei derived helpers dello snapshot review.
- Impatto: il dominio review manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Bridges/CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift`.
  2. Verificare che il file contenga solo due computed property di forwarding.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il bridge di projection dello snapshot viveva in un file dedicato.
- Risultato atteso: le computed property devono stare in `CodeReviewSessionSnapshot+Derived.swift`, accanto agli altri derived helpers dello snapshot.
- Causa probabile: tranche precedenti avevano drenato helper review più grandi, lasciando questo bridge residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Session`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Bridges`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - mutazioni dello snapshot
- Moduli confinanti da verificare:
  - `VerifiedFindingsServiceTests`
  - `VerifiedFindingsStatusServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente di service e status riutilizzata
- Strategia di fix minimo:
  - spostare le due computed property in `CodeReviewSessionSnapshot+Derived.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-projection-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-projection-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-projection-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-projection-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-projection-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests`
- Commit previsto: `refactor(review): fold session projection bridge into snapshot derived`

## Fix applicato
- `verifiedFindingsProjection` e `canonicalVerifiedFindingsSnapshot` spostati in `CodeReviewSessionSnapshot+Derived.swift`
- rimosso `CodeReviewSessionSnapshot+VerifiedFindingsProjection.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
