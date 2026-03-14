# P2 - Il bridge Rust snapshot del session state restava isolato in un file pipeline dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewSessionState+RustSnapshot.swift` restava un file Swift non-UI dedicato nel dominio review pipeline pur contenendo solo la sostituzione canonica dello snapshot sul session state.
- Sintomo: `replaceCanonicalSnapshot(_:)` viveva ancora in un extension file separato dal type owner `CodeReviewSessionState`.
- Impatto: il dominio review core manteneva un file legacy Swift in piu' senza ownership autonoma, rallentando il drenaggio non-UI del dominio review.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/CodeReviewSessionState+RustSnapshot.swift`.
  2. Verificare che il file contenga solo `replaceCanonicalSnapshot(_:)`.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: il bridge Rust snapshot viveva in un file pipeline dedicato.
- Risultato atteso: `replaceCanonicalSnapshot(_:)` deve stare in `CodeReviewSessionState.swift`, accanto allo state owner.
- Causa probabile: tranche precedenti avevano drenato helper review più visibili, lasciando questo bridge residuale in un file separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview`
  - `Tests/CoderEngineTests/CodeReview`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - UI panel
  - verified findings
- Moduli confinanti da verificare:
  - `CodeReviewSessionStateTests`
  - `CodeReviewSessionStateTests+TerminalLifecycle`
- Test da aggiungere o aggiornare:
  - `CodeReviewSessionStateTests+TerminalLifecycle`
- Strategia di fix minimo:
  - spostare `replaceCanonicalSnapshot(_:)` in `CodeReviewSessionState.swift`
  - aggiungere una regression sul replace per sessione coincidente
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/session-state-snapshot-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-state-snapshot-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/session-state-snapshot-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/session-state-snapshot-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/session-state-snapshot-source-packages" -only-testing:CoderEngineTests/CodeReviewSessionStateTests/testReplaceCanonicalSnapshotReplacesStateForMatchingSession`
- Commit previsto: `refactor(review): fold session state snapshot bridge into state actor`

## Fix applicato
- `replaceCanonicalSnapshot(_:)` spostato in `CodeReviewSessionState.swift`
- aggiunta regression in `CodeReviewSessionStateTests+TerminalLifecycle.swift`
- rimosso `CodeReviewSessionState+RustSnapshot.swift` dal filesystem e dal progetto Xcode

## Esito
- il dominio review core riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
