# P2 - Il bridge Rust di completion/launch review restava ancora isolato in un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+RustCompletionFinalization.swift` era rimasto come file Swift non-UI separato, pur contenendo solo bridge verso runtime Rust per planning launch e patch finalization.
- Sintomo: il panel review manteneva un file legacy in piu' senza logica Swift sostanziale, anche se il comportamento era gia' controllato da Rust.
- Impatto: il backlog del prefisso review restava piu' alto del necessario e il boundary Swift risultava piu' frammentato.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift`.
  2. Verificare che esponga solo wrapper `ReviewCoreBridge.call(...)` per launch planning e patch finalization.
  3. Notare che il file resta legacy non-UI separato nel conteggio del panel review.
- Risultato attuale: il bridge completion/launch stava ancora in un file Swift dedicato.
- Risultato atteso: i bridge review gia' Rust-backed devono essere collocati in file Swift legacy gia' esistenti, senza introdurre o mantenere file dedicati superflui.
- Causa probabile: tranche precedenti avevano spostato il comportamento a Rust ma non avevano ancora consolidato il boundary residuo sul flusso launch/targeted-fix/completion.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - nuove API Rust
  - logica business del panel
  - UI
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
  - `CodeReviewPanelStore+Launch.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - targeted tests `SoloCodeAppTests` selezionati da `scripts/solocode-validate`
- Strategia di fix minimo:
  - spostare i bridge `patchFinalizationTargets(...)` in `CompletionFinalization`
  - spostare launch planning/session prefix helpers in `TargetedFix`
  - rimuovere il file dedicato e i relativi riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): merge rust completion launch bridge into existing store files`

## Fix applicato
- spostato `patchFinalizationTargets(...)` in `CodeReviewPanelStore+CompletionFinalization.swift`
- spostati launch planning, targeted fix planning e helper di session scope in `CodeReviewPanelStore+TargetedFix.swift`
- rimosso `CodeReviewPanelStore+RustCompletionFinalization.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `32` a `31`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
