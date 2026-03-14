# P2 - La redaction dei dati sensibili restava isolata in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `SensitiveDataRedactionService.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo regex e logica di redaction gia' usata dal dominio security.
- Sintomo: il servizio di masking di token, password e private key viveva in un file standalone.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SensitiveDataRedactionService.swift`.
  2. Verificare che il file contenga solo pattern di redaction e `redact(_:)`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: la redaction dei dati sensibili viveva in un file application dedicato.
- Risultato atteso: il servizio deve stare in `SecurityWorkflowService.swift`, accanto alle altre utility del dominio security.
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
  - `SensitiveDataRedactionServiceTests`
  - `SecurityWorkflowService`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente della redaction riutilizzata
- Strategia di fix minimo:
  - spostare `SensitiveDataRedactionService` in `SecurityWorkflowService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/sensitive-redaction-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/sensitive-redaction-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/sensitive-redaction-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/sensitive-redaction-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/sensitive-redaction-source-packages" -only-testing:CoderEngineTests/SensitiveDataRedactionServiceTests`
- Commit previsto: `refactor(review): fold sensitive redaction into security workflow service`

## Fix applicato
- `SensitiveDataRedactionService` spostato in `SecurityWorkflowService.swift`
- rimosso `SensitiveDataRedactionService.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
