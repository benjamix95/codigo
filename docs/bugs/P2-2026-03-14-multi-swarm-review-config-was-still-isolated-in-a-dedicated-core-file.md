# P2 - La multi-swarm review config restava isolata in un file core dedicato

## Bug Fix Record
- Categoria: B
- Bug: `MultiSwarmReviewConfig.swift` restava un file Swift non-UI dedicato nel dominio review core pur contenendo solo enum e config DTO del provider review.
- Sintomo: `ReviewEnabledPhase` e `MultiSwarmReviewConfig` vivevano ancora in un file standalone separato da `CodeReviewMultiSwarmProvider`.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/MultiSwarmReviewConfig.swift`.
  2. Verificare che il file contenga solo enum e config del provider review.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: la config multi-swarm viveva in un file core dedicato.
- Risultato atteso: `ReviewEnabledPhase` e `MultiSwarmReviewConfig` devono stare in `CodeReviewMultiSwarmProvider.swift`, accanto al provider che li usa come contratto primario.
- Causa probabile: tranche precedenti avevano drenato helper review piu' piccoli, lasciando questa config residuale in un file separato.
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
  - `CodeReviewMultiSwarmProvider`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: copertura esistente del pipeline riutilizzata
- Strategia di fix minimo:
  - spostare `ReviewEnabledPhase` e `MultiSwarmReviewConfig` in `CodeReviewMultiSwarmProvider.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/multi-swarm-config-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/multi-swarm-config-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/multi-swarm-config-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/multi-swarm-config-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/multi-swarm-config-source-packages" -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review): fold multi-swarm config into provider`

## Fix applicato
- `ReviewEnabledPhase` e `MultiSwarmReviewConfig` spostati in `CodeReviewMultiSwarmProvider.swift`
- rimosso `MultiSwarmReviewConfig.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
