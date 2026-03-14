# P2 - L'helper del review command payload restava isolato in un file session dedicato

## Bug Fix Record
- Categoria: B
- Bug: `SessionConfig+ReviewCommandPayload.swift` restava un file Swift non-UI dedicato nel dominio review session pur contenendo solo un computed property su `SessionConfig`.
- Sintomo: il payload `max_workers/max_rounds/analysis_backend/execution_backend/analysis_only` viveva ancora in un extension file separato.
- Impatto: il dominio review session manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Session/SessionConfig+ReviewCommandPayload.swift`.
  2. Verificare che il file contenga solo `SessionConfig.reviewCommandPayload`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: l'helper del payload review command viveva in un file session dedicato.
- Risultato atteso: il computed property deve stare in `ReviewSessionTypes.swift`, accanto a `SessionConfig`.
- Causa probabile: tranche precedenti avevano drenato file panel e bridge piu' urgenti ma non avevano ancora collassato questo helper residuale.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Session`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - handler MCP
  - UI panel
- Moduli confinanti da verificare:
  - `VerifiedFindingsStartCommandServiceTests`
  - `VerifiedFindingsStartCommandService`
- Test da aggiungere o aggiornare:
  - `VerifiedFindingsStartCommandServiceTests`
- Strategia di fix minimo:
  - spostare `reviewCommandPayload` dentro `SessionConfig` in `ReviewSessionTypes.swift`
  - aggiungere una regression esplicita sul contenuto del payload
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-command-payload-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-command-payload-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-command-payload-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-command-payload-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-command-payload-source-packages" -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests/testSessionConfigBuildsReviewCommandPayload`
- Commit previsto: `refactor(review): fold review command payload into session types`

## Fix applicato
- `SessionConfig.reviewCommandPayload` spostato in `ReviewSessionTypes.swift`
- aggiunta regression in `VerifiedFindingsStartCommandServiceTests.swift`
- rimosso `SessionConfig+ReviewCommandPayload.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review session riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
