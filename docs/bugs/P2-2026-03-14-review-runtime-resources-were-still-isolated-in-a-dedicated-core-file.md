# P2 - Le review runtime resources restavano isolate in un file core dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewRuntimeResources.swift` restava un file Swift non-UI dedicato nel dominio review core pur contenendo solo typealias e DTO usati dal runtime del pipeline.
- Sintomo: `ReviewPatchPreparationRuntime`, `CodeReviewRuntimeResources` e `CodeReviewRuntimeResolver` vivevano in un file standalone separato da `ReviewPipelineCoordinator+Runtime.swift`.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewRuntimeResources.swift`.
  2. Verificare che il file contenga solo i tipi del runtime review.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: i runtime resources vivevano in un file core dedicato.
- Risultato atteso: questi tipi devono stare in `ReviewPipelineCoordinator+Runtime.swift`, accanto alla funzione `currentRuntimeResources`.
- Causa probabile: tranche precedenti avevano drenato helper review piu' piccoli, lasciando questo DTO residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core`
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
  - `ReviewPipelineCoordinatorTests`
- Strategia di fix minimo:
  - spostare typealias e DTO in `ReviewPipelineCoordinator+Runtime.swift`
  - aggiungere una regression su `currentRuntimeResources` con `runtimeResolver`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/runtime-resources-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/runtime-resources-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/runtime-resources-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/runtime-resources-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/runtime-resources-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review): fold runtime resources into pipeline runtime`

## Fix applicato
- `ReviewPatchPreparationRuntime`, `CodeReviewRuntimeResources` e `CodeReviewRuntimeResolver` spostati in `ReviewPipelineCoordinator+Runtime.swift`
- aggiunta regression in `ReviewPipelineCoordinatorTests.swift`
- rimosso `CodeReviewRuntimeResources.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
