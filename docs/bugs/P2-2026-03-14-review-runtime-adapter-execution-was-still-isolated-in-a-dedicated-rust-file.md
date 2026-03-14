# P2 - Il runtime adapter execution restava isolato in un file Rust pipeline dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewRuntimeAdapter+Execution.swift` restava un file Swift non-UI separato pur contenendo solo metodi operativi dell'adapter Rust pipeline.
- Sintomo: il perimetro `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust` manteneva un file legacy dedicato senza ownership autonoma.
- Impatto: un file Swift non-UI in più nel dominio review rallentava il drenaggio verso Rust e aumentava la frammentazione del runtime adapter.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter+Execution.swift`.
  2. Verificare che contenga solo metodi dell'adapter `ReviewRuntimeAdapter`.
  3. Notare che il file compare ancora nel backlog Swift del dominio `CodeReview`.
- Risultato attuale: i metodi execution dell'adapter Rust vivevano in un file separato.
- Risultato atteso: i metodi dell'adapter devono stare in `ReviewRuntimeAdapter.swift`, accanto al resto del tipo.
- Causa probabile: tranche precedenti avevano drenato wrapper review più semplici lasciando questo adapter spezzato in due file.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust nativo
  - UI panel
  - persistence
- Moduli confinanti da verificare:
  - `ReviewPipelineRustDriver`
  - `ReviewPipelineCoordinatorTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso della copertura pipeline coordinator
- Strategia di fix minimo:
  - spostare i metodi execution nel file principale dell'adapter
  - rimuovere il file dal progetto Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter.swift,Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/ReviewRuntimeAdapter+Execution.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review): fold runtime adapter execution into adapter`

## Fix applicato
- metodi `runFixStage`, `runTests`, `scanModifiedFiles`, `runReReview` e `prepareVerifiedPatches` spostati in `ReviewRuntimeAdapter.swift`
- rimosso `ReviewRuntimeAdapter+Execution.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `CodeReview` riduce di un'altra unità il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
