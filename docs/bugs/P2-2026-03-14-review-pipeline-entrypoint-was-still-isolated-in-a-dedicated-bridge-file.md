# P2 - L'entrypoint del review pipeline restava isolato in un file bridge dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewMultiSwarmProvider+Pipeline.swift` restava un file Swift non-UI dedicato nel dominio review core pur contenendo solo un entrypoint di inoltro verso `ReviewPipelineCoordinator`.
- Sintomo: il bridge `runReviewPipeline(...)` viveva in un file standalone separato dal resto dei bridge pipeline del provider.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/CodeReviewMultiSwarmProvider+Pipeline.swift`.
  2. Verificare che il file contenga solo il forward dell'entrypoint verso `ReviewPipelineCoordinator.shared.run(...)`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: l'entrypoint del pipeline viveva in un file bridge dedicato.
- Risultato atteso: il bridge deve stare in `CodeReviewMultiSwarmProvider+PipelineBridge.swift`, accanto agli altri entrypoint del provider.
- Causa probabile: tranche precedenti avevano drenato helper review piu' piccoli, lasciando questo forward residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - verified findings
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProvider+PipelineBridge`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente del pipeline riutilizzata
- Strategia di fix minimo:
  - spostare `runReviewPipeline(...)` in `CodeReviewMultiSwarmProvider+PipelineBridge.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/pipeline-bridge-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-bridge-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/pipeline-bridge-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/pipeline-bridge-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/pipeline-bridge-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review): fold pipeline entrypoint into bridge`

## Fix applicato
- `runReviewPipeline(...)` spostato in `CodeReviewMultiSwarmProvider+PipelineBridge.swift`
- rimosso `CodeReviewMultiSwarmProvider+Pipeline.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
