# 2026-03-13 — Review panel Rust bridge collapse

## Modifiche
- consolidati i bridge Rust-backed del panel review dentro file Swift gia' esistenti:
  - chat extraction -> `CodeReviewPanelStore+ChatFindings.swift`
  - historical findings bridge -> `CodeReviewPanelStore+History.swift`
  - launch planning + patch finalization bridge -> `CodeReviewPanelStore+RustCompletionFinalization.swift`
- rimossi dal filesystem e dal progetto Xcode:
  - `CodeReviewPanelStore+RustChatFindings.swift`
  - `CodeReviewPanelStore+RustHistoricalFindings.swift`
  - `CodeReviewPanelStore+RustLaunchPlanning.swift`

## Comportamento
- nessun cambiamento funzionale del panel
- ridotto solo il boundary Swift residuo che era gia' mero pass-through verso Rust
- il budget gate review passa ora con backlog panel ridotto da `36` a `33`

## Validazione eseguita
- `scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift --format text`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift,scripts/validate_rust_cutover_boundary.sh,"Solo Code.xcodeproj/project.pbxproj"`

## Note
- questa tranche riduce il perimetro Swift senza introdurre nuovi file Swift non-UI
- il prossimo passo utile e' drenare un gruppo reale di store/coordinator ancora Swift-owned, non piu' solo wrapper Rust-backed
