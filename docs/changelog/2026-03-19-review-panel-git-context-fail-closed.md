# 2026-03-19 — Review panel Git context fail-closed

## Modifiche
- aggiunto lo stato [ReviewPanelGitContextStatus.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Shared/ReviewPanelGitContextStatus.swift) per modellare `idle/loading/loaded/notRepository/failed`
- introdotto il runtime dedicato [CodeReviewPanelStore+GitContext.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+GitContext.swift) per il fetch Rust del contesto Git del `CodeReviewPanel`
- semplificato [CodeReviewPanelStore+ProviderSelection.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ProviderSelection.swift) rimuovendo il fetch Git inline
- aggiornati i picker [ReviewPanelBranchSelector.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Git/ReviewPanelBranchSelector.swift) e [ReviewPanelCommitPicker.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Git/ReviewPanelCommitPicker.swift) per distinguere empty state, workspace non Git ed errore runtime
- aggiunti i test [ReviewPanelGitContextTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPanelGitContextTests.swift) con copertura su repo reale, non-repo, runtime disabilitato e `loadMoreCommits`
- aggiunto il supporto condiviso [ReviewCoreLibraryPathSupport.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewCoreLibraryPathSupport.swift) e aggiornate le suite review panel che dipendono dalla dylib Rust
- aggiornato [CodeReviewPanelLiveRunExecutionTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift) allineando l’aspettativa al contratto runtime Rust che preserva il tab `chat` al `run_finish` quando l’utente è già in chat
- estesa l’allowlist [rust-cutover-swift-allowlist.txt](/Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt) per i nuovi file test-only del boundary

## Comportamento
- il `CodeReviewPanel` ora fallisce in modo esplicito quando il contesto Git Rust non è disponibile
- i picker Git del panel review non mascherano più un errore come “nessun branch/commit”
- il caso “workspace attivo non Git” è distinguibile dal caso “runtime Rust non disponibile”
- i test panel-side review Rust non dipendono più dalla working directory del processo test

## Validazione eseguita
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination "platform=macOS" -only-testing:SoloCodeAppTests/ReviewPanelGitContextTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
- `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Shared/ReviewPanelGitContextStatus.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+GitContext.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ProviderSelection.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Git/ReviewPanelBranchSelector.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Views/Git/ReviewPanelCommitPicker.swift,Tests/SoloCodeAppTests/ReviewPanelGitContextTests.swift,Tests/SoloCodeAppTests/ReviewCoreLibraryPathSupport.swift,Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift,Tests/SoloCodeAppTests/ReviewPanelLifecycleE2ETests.swift,Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`

## Note
- nessun fallback a `GitService` Swift è stato reintrodotto
- il fix resta confinato al `CodeReviewPanel` e alla sua copertura test/doc
