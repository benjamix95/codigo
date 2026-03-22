## 2026-03-20

- reso tollerante il decode di [ReviewCoreChatExtractionResponse](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift) per non perdere i finding strutturati se lo `snapshot` Rust non e' decodificabile
- corretto il routing `close_finding` in [CodigoApp+CodeReviewCommands.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodigoApp+CodeReviewCommands.swift) usando il mutatore Rust diretto dello snapshot
- aggiunto fallback locale di `complete()` in [CodeReviewSessionState+Lifecycle.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/CodeReviewSessionState+Lifecycle.swift) quando il runtime Rust diventa indisponibile a review gia' avviata
- aggiornati i test in [CodeReviewPanelSessionScopingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift) e [CodeReviewSessionStateTests+TerminalLifecycle.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift)
