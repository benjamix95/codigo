# P2 - La admission policy dei verified findings restava isolata in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingAdmissionPolicy.swift` restava un file Swift non-UI dedicato in `VerifiedFindingsCore` pur contenendo solo regole statiche di ammissione gia' coerenti con gli altri servizi application.
- Sintomo: la policy `canPromoteFinding` e `requiresManualReview` viveva in un file standalone.
- Impatto: il dominio `VerifiedFindingsCore` manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingAdmissionPolicy.swift`.
  2. Verificare che il file contenga solo una policy statica senza dipendenze proprie.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: la admission policy viveva in un file application dedicato.
- Risultato atteso: la policy deve stare in un modulo application gia' esistente del dominio verified findings.
- Causa probabile: tranche precedenti avevano drenato bridge e helper review piu' urgenti, lasciando questa policy residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - MCP handler
  - UI panel
- Moduli confinanti da verificare:
  - `VerifiedFindingAdmissionPolicyTests`
  - `VerifiedFindingsStatusService`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente della policy riutilizzata
- Strategia di fix minimo:
  - spostare `VerifiedFindingAdmissionPolicy` in `VerifiedFindingsStatusService.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/verified-admission-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/verified-admission-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/verified-admission-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/verified-admission-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/verified-admission-source-packages" -only-testing:CoderEngineTests/VerifiedFindingAdmissionPolicyTests`
- Commit previsto: `refactor(review): fold verified admission policy into status service`

## Fix applicato
- `VerifiedFindingAdmissionPolicy` spostata in `VerifiedFindingsStatusService.swift`
- rimosso `VerifiedFindingAdmissionPolicy.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `VerifiedFindingsCore` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
