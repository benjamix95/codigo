# 2026-03-13 — Review panel modes and chat threads collapse

## Modifiche
- rimosso [CodeReviewPanelStore+ModesAndChatThreads.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift)
- consolidati mode selection, chat session key, thread actions e deferral della conversazione in [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift)
- aggiornato [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per rimuovere il file dal target
- aggiunte regression mirate in [ReviewPanelChatSessionStoreTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPanelChatSessionStoreTests.swift) per mode selection e chat thread actions del panel

## Comportamento
- nessun cambiamento funzionale previsto del panel chat
- preservato il deferral asincrono di `handleIncomingChatConversation`
- preservata la gestione locale di selected modes e thread chat

## Validazione eseguita
- `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
- `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-modes-chat-tranche-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-modes-chat-tranche-source-packages"`
- `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-modes-chat-tranche-derived-data/Build/Products/Debug"`
- `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-modes-chat-tranche-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-modes-chat-tranche-source-packages" -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelStoreRestoresCachedChatSessionState -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelDefaultsToFindingsTabAndUnifiedModes`
- `scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`

## Note
- questa tranche riduce il backlog Swift non-UI del panel review senza introdurre nuovi bridge
- il runner `xcodebuild test` diretto sul workspace resta meno affidabile del flusso `build-for-testing` gia' usato dal validator del repo
- il prossimo target sensato resta uno dei file store ancora davvero Swift-owned, con priorita' plausibile su `CodeReviewPanelStore+ProviderSelection.swift`
