# P2 - Il review pipeline coordinator restava isolato in un file runtime dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewPipelineCoordinator.swift` restava un file Swift non-UI dedicato nel dominio review pipeline pur contenendo solo l'actor e l'entrypoint principale `run(...)`.
- Sintomo: il coordinatore della pipeline viveva ancora separato dal modulo runtime che contiene `currentRuntimeResources` e gli helper di esecuzione.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift`.
  2. Verificare che il file contenga solo l'actor e il metodo `run(...)`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il coordinatore runtime viveva in un file dedicato.
- Risultato atteso: l'actor deve stare in `ReviewPipelineCoordinator+Runtime.swift`, accanto agli helper di runtime della stessa pipeline.
- Causa probabile: tranche precedenti avevano drenato helper review minori, lasciando questo actor residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - verified findings
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `ReviewPipelineCoordinator+Runtime`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente del pipeline riutilizzata
- Strategia di fix minimo:
  - spostare `ReviewPipelineCoordinator` in `ReviewPipelineCoordinator+Runtime.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/pipeline-coordinator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-coordinator-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/pipeline-coordinator-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/pipeline-coordinator-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-coordinator-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review): fold pipeline coordinator into runtime`

## Fix applicato
- `ReviewPipelineCoordinator` spostato in `ReviewPipelineCoordinator+Runtime.swift`
- rimosso `ReviewPipelineCoordinator.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
