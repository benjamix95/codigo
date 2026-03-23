## 2026-03-22

## Modifiche
- hardening del validator in [scripts/solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate):
  - array vuoti sicuri sotto Bash 3.2
  - parsing corretto di `--files` con singolo path
  - `DerivedData` e source packages per-processo per evitare lock concorrenti
- aggiunta regressione dedicata in [SoloCodeValidateScriptTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Validation/SoloCodeValidateScriptTests.swift) e wiring al target in [project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj)
- fallback lifecycle confinato in [CodeReviewSessionState.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/CodeReviewSessionState.swift) per `start/complete/fail` quando il bridge Rust non risponde
- allineamento dei test Rust live in [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
- riallineamento dei review/bughunter harness Rust-first in:
  - [CoderIDEMCPServerApp+ReviewHarnessCommands.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Support/ReviewMCPHarness/CoderIDEMCPServerApp+ReviewHarnessCommands.swift)
  - [CoderIDEMCPServerApp+ReviewHarnessReads.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Support/ReviewMCPHarness/CoderIDEMCPServerApp+ReviewHarnessReads.swift)
  - [CoderIDEMCPServerApp+BugHunterHarness.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Support/ReviewMCPHarness/CoderIDEMCPServerApp+BugHunterHarness.swift)
- bootstrap Rust esplicito nelle suite plan/workflow:
  - [CoderIDEMCPServerPlanToolsTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CoderIDEMCPServerPlanToolsTests.swift)
  - [CodeReviewMultiSwarmProviderTests+TaskExtraction.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+TaskExtraction.swift)
- correzione della semantica turn/reasoning in:
  - [CodexCLIProvider+Events.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/StreamSupport/CodexCLIProvider+Events.swift)
  - [CodexCLIProvider+Events+Dedup.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/StreamSupport/CodexCLIProvider+Events+Dedup.swift)
- riduzione della race Postgres nei test storici in [ReviewPanelFindingsHistoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift)

## Test
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Release' -destination 'platform=macOS'`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SoloCodeValidateScriptTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests/testLiveDismissUsesRustMutatorAndPersistsSnapshot`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testDeferredReviewFailsWhenRustFinalizationRuntimeBecomesUnavailable`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CoderIDEMCPServerPlanToolsTests -only-testing:CoderEngineTests/BugHunterHandlerTests/testBugHunterStatusIncludesVerifiedFindingsCounters -only-testing:CoderEngineTests/BugHunterWorkflowServiceTests/testQueueLifecycleCommandRoutesApplyThroughSharedLifecycle`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests/testAgentMessageProducesOperationalUpdateBeforeFinalTurnText -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests/testMultiTurnMovesIntermediateTextToReasoning -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests/testSingleTurnDoesNotEmitTextReplace -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests/testThreeTurnKeepsOnlyLastTurnVisible`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsReadsPersistedWorkspaceHistory`
- `scripts/solocode-validate --trigger ciFull --workspace /Users/benjaminstoica/SoloCode --format text`

## Rischio controllato
- nessun refactor largo: ogni fix resta confinato a validator, harness/test bootstrap, lifecycle review o parser Codex
- nessun cambiamento intenzionale al contratto utente delle feature fuori dai failure riprodotti
