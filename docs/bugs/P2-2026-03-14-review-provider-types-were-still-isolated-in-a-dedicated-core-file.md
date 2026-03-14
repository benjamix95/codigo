# P2 - I provider types review restavano isolati in un file core dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewMultiSwarmProvider+Types.swift` restava un file Swift non-UI dedicato nel dominio review core pur contenendo solo tipi e helper del provider multi-swarm.
- Sintomo: `ReviewTask`, `ReviewFindingsState`, `ReviewPipelineError`, `CodeReviewStreamTextAccumulator` e gli helper di display worker vivevano ancora in un file separato dal provider che li possiede.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+Types.swift`.
  2. Verificare che il file contenga solo tipi e helper statici del provider review.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: i provider types review vivevano in un file core dedicato.
- Risultato atteso: questi tipi devono stare in `CodeReviewMultiSwarmProvider.swift`, accanto al provider che li usa come contratto interno primario.
- Causa probabile: tranche precedenti avevano drenato helper review più piccoli, lasciando questi tipi residuali in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - verified findings
- Moduli confinanti da verificare:
  - `CodeReviewMultiSwarmProviderTests+Outcomes`
  - `CodeReviewStreamTextAccumulatorTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente del provider riutilizzata
- Strategia di fix minimo:
  - spostare tipi e helper in `CodeReviewMultiSwarmProvider.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/provider-types-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/provider-types-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/provider-types-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/provider-types-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/provider-types-source-packages" -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/CodeReviewStreamTextAccumulatorTests`
- Commit previsto: `refactor(review): fold provider types into multi-swarm provider`

## Fix applicato
- tipi e helper di `CodeReviewMultiSwarmProvider+Types.swift` spostati in `CodeReviewMultiSwarmProvider.swift`
- rimosso `CodeReviewMultiSwarmProvider+Types.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
