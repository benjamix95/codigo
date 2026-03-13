# P2 - Gli helper di worker ordering review restavano isolati in un file engine dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewMultiSwarmProvider+WorkerOrdering.swift` restava un file Swift non-UI dedicato nel dominio review engine pur contenendo solo tre helper statici di ordinamento e classificazione display.
- Sintomo: la logica di worker ordering e debug label del provider multi-swarm viveva ancora in un extension file separato.
- Impatto: il dominio review engine manteneva un file legacy Swift in piu' senza alcuna ownership autonoma di comportamento.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+WorkerOrdering.swift`.
  2. Verificare che il file contenga solo helper statici del provider gia' coerenti con `CodeReviewMultiSwarmProvider+Types.swift`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: gli helper di ordinamento worker vivevano in un file engine dedicato.
- Risultato atteso: gli helper devono stare nel modulo `+Types.swift`, senza un file standalone aggiuntivo.
- Causa probabile: tranche precedenti avevano drenato wrapper panel e bridge engine piu' urgenti ma non avevano ancora collassato questo file residuo.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - pipeline review
  - runtime Rust
  - UI panel
- Moduli confinanti da verificare:
  - `CodeReviewMultiSwarmProviderTests+Outcomes`
  - `CodeReviewPanelValidationTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente su ordinamento naturale worker riutilizzata
- Strategia di fix minimo:
  - spostare i tre helper statici in `CodeReviewMultiSwarmProvider+Types.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-worker-ordering-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-worker-ordering-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-worker-ordering-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-worker-ordering-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-worker-ordering-source-packages" -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testSortedWorkerTaskIDsForDisplay_usesNaturalOrdering -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testSortedReviewWorkerPlanActivitiesForDisplay_usesNaturalWorkerOrdering`
- Commit previsto: `refactor(review): fold worker ordering helpers into provider types`

## Fix applicato
- helper `findingsStateDebugLabel`, `sortedWorkerTaskIDsForDisplay` e `sortWorkerTaskIDForDisplay` spostati in `CodeReviewMultiSwarmProvider+Types.swift`
- rimosso `CodeReviewMultiSwarmProvider+WorkerOrdering.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review engine riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
