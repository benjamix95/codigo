# P2 - I pipeline ledger models restavano isolati in un file session dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewPipelineLedgerModels.swift` restava un file Swift non-UI separato pur definendo solo i tipi ledger usati dallo snapshot review.
- Sintomo: il dominio `CodeReview` manteneva un file legacy dedicato per i modelli `phaseLedger` e `fileLedger`.
- Impatto: debito Swift non-UI più alto e ownership distribuita tra snapshot e tipi ledger.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Session/ReviewPipelineLedgerModels.swift`.
  2. Verificare che il file contenga solo `ReviewPipelineLedgerStatus`, `ReviewPipelinePhaseLedgerEntry` e `ReviewPipelineFileLedgerEntry`.
  3. Notare che i tipi sono usati direttamente da `CodeReviewSessionSnapshot`.
- Risultato attuale: i tipi ledger vivevano in un file separato.
- Risultato atteso: i ledger models devono stare accanto allo snapshot review in `CodeReviewSessionSnapshot+Derived.swift`.
- Causa probabile: tranche precedenti avevano drenato wrapper review più urgenti lasciando i tipi ledger residuali separati.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Session`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/changelog`
  - `docs/migration`
- Non-scope:
  - runtime Rust
  - panel store logic
  - persistence
- Moduli confinanti da verificare:
  - `CodeReviewSessionSnapshot`
  - build `Solo Code-Debug`
  - build `CoderEngineTests-Debug`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; build engine e app-side usati come smoke sui contratti dei modelli
- Strategia di fix minimo:
  - spostare i tre tipi ledger in `CodeReviewSessionSnapshot+Derived.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionSnapshot+Derived.swift,Engine/CoderEngine/Sources/CodeReview/Session/ReviewPipelineLedgerModels.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- Commit previsto: `refactor(review): fold pipeline ledger models into session snapshot`

## Fix applicato
- `ReviewPipelineLedgerStatus`, `ReviewPipelinePhaseLedgerEntry` e `ReviewPipelineFileLedgerEntry` spostati in `CodeReviewSessionSnapshot+Derived.swift`
- rimosso `ReviewPipelineLedgerModels.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio `CodeReview` riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
