# P2 - Il verified findings session envelope restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsSessionEnvelope.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo il DTO envelope del dominio verified findings.
- Sintomo: il contenitore `sessionId/canonicalSnapshot/projectionSnapshot/schemaVersion` viveva in un file standalone separato dal service che lo risolve e lo usa come entrypoint principale.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionEnvelope.swift`.
  2. Verificare che il file contenga solo il DTO envelope.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il session envelope viveva in un file application dedicato.
- Risultato atteso: il DTO deve stare in `VerifiedFindingsService.swift`, accanto al service che lo risolve e ne espone le projection.
- Causa probabile: tranche precedenti avevano drenato helper review piu' urgenti, lasciando questo DTO residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - projection builder
  - UI panel
- Moduli confinanti da verificare:
  - `VerifiedFindingsServiceTests`
  - `VerifiedFindingsReplayServiceTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente su service e replay riutilizzata
- Strategia di fix minimo:
  - spostare `VerifiedFindingsSessionEnvelope` in `VerifiedFindingsService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-envelope-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-envelope-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-envelope-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-envelope-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-envelope-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests`
- Commit previsto: `refactor(review): fold verified session envelope into service`

## Fix applicato
- `VerifiedFindingsSessionEnvelope` spostato in `VerifiedFindingsService.swift`
- rimosso `VerifiedFindingsSessionEnvelope.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
