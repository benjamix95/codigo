# P2 - Il Git context del review panel veniva ancora caricato tramite `GitService` Swift

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+GitContext.swift` continuava a usare `GitService` Swift per risolvere root, branch locali/remoti, commit history e branch corrente del panel review.
- Sintomo: il panel review manteneva un file Swift non-UI dedicato sia al fetch Git sia alla gestione delle selezioni branch/commit.
- Impatto: il backlog del prefisso review restava piu' alto e il caricamento del contesto Git non era ancora passato dal boundary Rust.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+GitContext.swift`.
  2. Verificare che `refreshGitContext()` e `loadMoreCommits()` chiamino direttamente `GitService`.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: il panel review caricava branch/commit tramite servizi Swift.
- Risultato atteso: il fetch Git del panel review deve passare da un entrypoint Rust, lasciando a Swift solo aggiornamento di stato e selezione locale.
- Causa probabile: le tranche precedenti avevano drenato soprattutto wrapper e orchestrazione panel, ma non il contesto Git.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Native/RustCore`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - servizi Git generali fuori dal panel review
  - UI dei picker branch/commit
  - workflow patch
- Moduli confinanti da verificare:
  - `ReviewPanelBranchSelector`
  - `ReviewPanelCommitPicker`
  - `ChatPanelView+PartF_CodeReviewActions`
  - boundary review core FFI
- Test da aggiungere o aggiornare:
  - test Rust sul parsing branches/commit history
  - validation review con budget gate attivo
- Strategia di fix minimo:
  - introdurre `review_core_panel_git_context` in Rust
  - spostare `refreshGitContext()` / `loadMoreCommits()` su `ReviewCoreBridge`
  - assorbire le selection action e i piccoli scheduler in file store gia' esistenti
  - rimuovere `CodeReviewPanelStore+GitContext.swift` e i riferimenti Xcode
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_git_context -- --nocapture`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ProviderSelection.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Settings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+GitContext.swift,Native/RustCore/src/lib.rs,Native/RustCore/src/ffi/mod.rs,Native/RustCore/src/review_git_context.rs,Native/RustCore/src/ffi/review_panel_git.rs,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): move git context loading behind rust boundary`

## Fix applicato
- aggiunto il modulo Rust `review_git_context` con parsing di branch locali/remoti, commit history e branch corrente
- aggiunto l'entrypoint FFI `review_core_panel_git_context`
- spostati `refreshGitContext()` e `loadMoreCommits()` in `CodeReviewPanelStore+ProviderSelection.swift`
- spostati `historyAutomaticRefreshKey` e scheduler history in `CodeReviewPanelStore+Settings.swift`
- spostato `ReviewPanelLaunchRequestStore` in `CodeReviewPanelStore+TargetedFix.swift`
- rimosso `CodeReviewPanelStore+GitContext.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `26` a `25`
- nessuna nuova violazione Swift non-UI
- build, test Rust e test selettivi review restano verdi
