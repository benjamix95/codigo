# P2 - Il Git context del Code Review Panel falliva in silenzio dopo il cutover Rust

## Bug Fix Record
- Categoria: B
- Bug: il `CodeReviewPanel` mostrava branch, commit e remoti vuoti quando il fetch Rust del contesto Git falliva o il workspace non era un repository.
- Sintomo: i picker Git del panel review mostravano solo empty state, senza errore esplicito e senza distinzione tra repo assente e runtime Rust indisponibile.
- Impatto: impossibile usare scope branch/commit nel panel review; `currentGitBranch` restava vuoto anche se il `GitPanel` classico funzionava.
- Gravità: P2
- Steps to reproduce:
  1. Aprire il `CodeReviewPanel`.
  2. Lasciare come workspace attivo una cartella non Git oppure forzare il runtime review Rust non disponibile.
  3. Aprire i picker branch/commit del panel review.
- Risultato attuale: empty state silenzioso con liste vuote.
- Risultato atteso: errore esplicito o stato “workspace non Git”, senza fallback Swift.
- Causa probabile: `refreshGitContext()` e `loadMoreCommits()` scartavano sia `ReviewCoreBridge.call(...) == nil` sia `response.error`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/**`
  - `Tests/SoloCodeAppTests/*ReviewPanel*`
  - `Config/validation/rust-cutover-swift-allowlist.txt`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - `GitPanelStore` classico
  - fallback operativo a `GitService` Swift
  - crate Rust `Native/RustCore`
- Moduli confinanti da verificare:
  - `ReviewPanelBranchSelector`
  - `ReviewPanelCommitPicker`
  - `CodeReviewPanelLiveRunExecutionTests`
  - `ReviewPanelLifecycleE2ETests`
- Test da aggiungere o aggiornare:
  - repo Git reale
  - cartella non Git
  - runtime Rust disabilitato
  - `loadMoreCommits(limit:)` oltre il limite iniziale
- Strategia di fix minimo:
  - introdurre stato esplicito `ReviewPanelGitContextStatus`
  - far fallire il panel in modo diagnostico e fail-closed
  - coprire il flusso Git panel-side con test dedicati
- Verifica post-fix:
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination "platform=macOS" -only-testing:SoloCodeAppTests/ReviewPanelGitContextTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files <csv>`
- Commit previsto: `fix(review): fail closed on rust git context loading`

## Esito
- aggiunto stato Git esplicito nel panel review con casi `loading`, `loaded`, `notRepository`, `failed`
- rimosso l’empty state silenzioso per i failure path Rust
- nessun fallback a Swift introdotto
- aggiunta copertura app-side dedicata del Git context
