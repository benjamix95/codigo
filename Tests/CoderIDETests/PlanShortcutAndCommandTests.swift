import AppKit
import XCTest
@testable import CoderIDE

final class PlanShortcutAndCommandTests: XCTestCase {
    func testParsePlanCommandInputWithExplicitPrompt() {
        let parsed = parsePlanCommandInput("  /plan create a rollout strategy  ")
        XCTAssertTrue(parsed.forcePlanInline)
        XCTAssertEqual(parsed.displayedInput, "create a rollout strategy")
        XCTAssertEqual(parsed.llmPromptInput, "create a rollout strategy")
    }

    func testParsePlanCommandInputWithEmptyPromptUsesFallback() {
        let parsed = parsePlanCommandInput("/plan")
        XCTAssertTrue(parsed.forcePlanInline)
        XCTAssertTrue(parsed.displayedInput.contains("Generate a structured plan"))
        XCTAssertTrue(parsed.llmPromptInput.contains("Generate a structured plan"))
    }

    func testParsePlanCommandInputWithoutCommandKeepsOriginal() {
        let parsed = parsePlanCommandInput("fix parser plan panel")
        XCTAssertFalse(parsed.forcePlanInline)
        XCTAssertEqual(parsed.displayedInput, "fix parser plan panel")
        XCTAssertEqual(parsed.llmPromptInput, "fix parser plan panel")
    }

    func testParsePlanCommandInputDoesNotTriggerForPlannerPrefix() {
        let parsed = parsePlanCommandInput("/planner analyze the parser")
        XCTAssertFalse(parsed.forcePlanInline)
        XCTAssertEqual(parsed.displayedInput, "/planner analyze the parser")
        XCTAssertEqual(parsed.llmPromptInput, "/planner analyze the parser")
    }

    func testParsePlanCommandInputDoesNotTriggerForPlanxPrefix() {
        let parsed = parsePlanCommandInput("/planx analyze the parser")
        XCTAssertFalse(parsed.forcePlanInline)
        XCTAssertEqual(parsed.displayedInput, "/planx analyze the parser")
        XCTAssertEqual(parsed.llmPromptInput, "/planx analyze the parser")
    }

    func testShouldUseClarificationPromptInPlanMode() {
        XCTAssertTrue(
            shouldUseClarificationPrompt(
                coderMode: .plan,
                planningState: .awaitingClarification(questions: "## Clarification questions\n1. A?\n2. B?"),
                shouldRunPlanInline: false
            )
        )
    }

    func testShouldUseClarificationPromptInInlinePlanMode() {
        XCTAssertTrue(
            shouldUseClarificationPrompt(
                coderMode: .agent,
                planningState: .awaitingClarification(questions: "## Clarification questions\n1. A?\n2. B?"),
                shouldRunPlanInline: true
            )
        )
    }

    func testShouldUseClarificationPromptFalseWhenNotAwaitingClarification() {
        XCTAssertFalse(
            shouldUseClarificationPrompt(
                coderMode: .agent,
                planningState: .awaitingChoice(planContent: "plan", options: []),
                shouldRunPlanInline: true
            )
        )
    }

    func testIsShiftTabShortcutPositiveWithTabKeyCode() {
        let flags: NSEvent.ModifierFlags = [.shift]
        XCTAssertTrue(isShiftTabShortcut(flags: flags, charsIgnoringModifiers: "\t", keyCode: 48))
    }

    func testIsShiftTabShortcutPositiveWithBacktabChar() {
        let flags: NSEvent.ModifierFlags = [.shift]
        XCTAssertTrue(isShiftTabShortcut(flags: flags, charsIgnoringModifiers: "\u{19}", keyCode: 0))
    }

    func testIsShiftTabShortcutNegativeWhenCommandPressed() {
        let flags: NSEvent.ModifierFlags = [.shift, .command]
        XCTAssertFalse(isShiftTabShortcut(flags: flags, charsIgnoringModifiers: "\u{19}", keyCode: 48))
    }

    func testIsCmdShiftPShortcutPositive() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        XCTAssertTrue(isCmdShiftPShortcut(flags: flags, charsIgnoringModifiers: "P"))
    }

    func testIsCmdShiftPShortcutNegativeWithoutShift() {
        let flags: NSEvent.ModifierFlags = [.command]
        XCTAssertFalse(isCmdShiftPShortcut(flags: flags, charsIgnoringModifiers: "P"))
    }

    func testEvaluateShiftTabPlanShortcutFirstPressImmediatelyPrependsPlanCommand() {
        let result = evaluateShiftTabPlanShortcut(currentInputText: "fix parser")

        XCTAssertEqual(result.nextInputText, "/plan fix parser")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertTrue(result.shouldEnablePlanToggle)
    }

    func testEvaluateShiftTabPlanShortcutWithPrimedStateStillPrependsPlanCommand() {
        let result = evaluateShiftTabPlanShortcut(currentInputText: "analyze the refactor")

        XCTAssertEqual(result.nextInputText, "/plan analyze the refactor")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertTrue(result.shouldEnablePlanToggle)
    }

    func testEvaluateShiftTabPlanShortcutWithEmptyInputSetsPlanOnly() {
        let result = evaluateShiftTabPlanShortcut(currentInputText: "   ")

        XCTAssertEqual(result.nextInputText, "/plan ")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertTrue(result.shouldEnablePlanToggle)
    }

    func testEvaluateShiftTabPlanShortcutKeepsExistingPlanPrefix() {
        let result = evaluateShiftTabPlanShortcut(currentInputText: "/plan roadmap fix")

        XCTAssertEqual(result.nextInputText, "/plan roadmap fix")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertTrue(result.shouldEnablePlanToggle)
    }

    func testEvaluateShiftTabPlanShortcutAfterExpiryStillPrependsPlanCommand() {
        let result = evaluateShiftTabPlanShortcut(currentInputText: "nuovo task")

        XCTAssertEqual(result.nextInputText, "/plan nuovo task")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertTrue(result.shouldEnablePlanToggle)
    }

    func testShouldOpenPlanPanelAfterShiftTabWhenPanelClosed() {
        XCTAssertTrue(
            shouldOpenPlanPanelAfterShiftTab(
                shouldEnablePlanToggle: true,
                currentShowPlanPanel: false
            )
        )
    }

    func testShouldOpenPlanPanelAfterShiftTabWhenPanelAlreadyOpenOrToggleDisabled() {
        XCTAssertFalse(
            shouldOpenPlanPanelAfterShiftTab(
                shouldEnablePlanToggle: true,
                currentShowPlanPanel: true
            )
        )
        XCTAssertFalse(
            shouldOpenPlanPanelAfterShiftTab(
                shouldEnablePlanToggle: false,
                currentShowPlanPanel: false
            )
        )
    }

    func testEvaluateCmdShiftPPlanShortcutFirstPressEnablesInlinePlanOnly() {
        let result = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: false,
            currentShowPlanPanel: false
        )
        XCTAssertTrue(result.nextPlanToggleEnabled)
        XCTAssertFalse(result.nextShowPlanPanel)
    }

    func testEvaluateCmdShiftPPlanShortcutSecondPressOpensPanel() {
        let result = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: true,
            currentShowPlanPanel: false
        )
        XCTAssertTrue(result.nextPlanToggleEnabled)
        XCTAssertTrue(result.nextShowPlanPanel)
    }

    func testEvaluateCmdShiftPPlanShortcutThirdPressDisablesAll() {
        let result = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: true,
            currentShowPlanPanel: true
        )
        XCTAssertFalse(result.nextPlanToggleEnabled)
        XCTAssertFalse(result.nextShowPlanPanel)
    }

    func testPlanExecutionProviderWhitelist() {
        XCTAssertTrue(isPlanExecutionProviderIdAllowed("codex-cli"))
        XCTAssertTrue(isPlanExecutionProviderIdAllowed("claude-cli"))
        XCTAssertTrue(isPlanExecutionProviderIdAllowed("gemini-cli"))
        XCTAssertTrue(isPlanExecutionProviderIdAllowed("openai-api"))
        XCTAssertTrue(isPlanExecutionProviderIdAllowed("openrouter-api"))
        XCTAssertFalse(isPlanExecutionProviderIdAllowed("not-a-provider"))
    }

    func testShouldHandlePlanKeyboardShortcutOnlyWhenInputFocused() {
        XCTAssertTrue(shouldHandlePlanKeyboardShortcut(isInputFocused: true))
        XCTAssertFalse(shouldHandlePlanKeyboardShortcut(isInputFocused: false))
    }

    func testShouldSyncModeOnProviderChangeHonorsUserPickerSuppression() {
        XCTAssertFalse(shouldSyncModeOnProviderChange(suppressForUserPicker: true))
        XCTAssertTrue(shouldSyncModeOnProviderChange(suppressForUserPicker: false))
    }

    func testShouldFallbackToPreferredProviderWhenSelectedNotAuthenticated() {
        XCTAssertTrue(
            shouldFallbackToPreferredProvider(
                selectedProviderIsAuthenticated: false,
                hasPreferredAuthenticatedFallback: true
            )
        )
        XCTAssertFalse(
            shouldFallbackToPreferredProvider(
                selectedProviderIsAuthenticated: true,
                hasPreferredAuthenticatedFallback: true
            )
        )
        XCTAssertFalse(
            shouldFallbackToPreferredProvider(
                selectedProviderIsAuthenticated: false,
                hasPreferredAuthenticatedFallback: false
            )
        )
    }

    func testPlanPanelAutoOpenPolicy() {
        XCTAssertFalse(shouldAutoOpenPlanPanel(trigger: .planStepUpdate))
        XCTAssertTrue(shouldAutoOpenPlanPanel(trigger: .flowStarted))
        XCTAssertTrue(shouldAutoOpenPlanPanel(trigger: .awaitingClarification))
        XCTAssertTrue(shouldAutoOpenPlanPanel(trigger: .awaitingChoice))
    }

    func testShouldAllowStartingPlanBuildBlocksWhenAnotherBuildTaskIsActive() {
        XCTAssertFalse(
            shouldAllowStartingPlanBuild(
                isLoadingCurrentConversation: false,
                phase: .readyToBuild,
                activeBuildPlanConversationId: UUID(),
                hasActiveBuildTask: true
            )
        )
    }

    func testShouldAllowStartingPlanBuildAllowsWhenNoActiveBuildTask() {
        XCTAssertTrue(
            shouldAllowStartingPlanBuild(
                isLoadingCurrentConversation: false,
                phase: .readyToBuild,
                activeBuildPlanConversationId: nil,
                hasActiveBuildTask: false
            )
        )
    }

    func testIsPlanBuildContextMatchesActiveBuildConversationEvenWhenPhaseIdle() {
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()
        XCTAssertTrue(
            isPlanBuildContext(
                conversationId: buildPlanConversationId,
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
        XCTAssertTrue(
            isPlanBuildContext(
                conversationId: buildAgentConversationId,
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
        XCTAssertFalse(
            isPlanBuildContext(
                conversationId: UUID(),
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
    }

    func testShouldEnableTaskPanelForOperationalModes() {
        XCTAssertTrue(shouldEnableTaskPanelForMode(.agent))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.debug))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.plan))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.codeReviewMultiSwarm))
        XCTAssertFalse(shouldEnableTaskPanelForMode(.ide))
        XCTAssertFalse(shouldEnableTaskPanelForMode(.mcpServer))
    }

    func testResolveDebugFlowPhaseAliasSupportsLegacyPhaseNames() {
        XCTAssertEqual(resolveDebugFlowPhaseAlias("analyzing"), .describing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("reproduce"), .reproducing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("fix"), .fixing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("instrument"), .instrumenting)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("verify"), .verifying)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("resolve"), .resolved)
        XCTAssertNil(resolveDebugFlowPhaseAlias("unexpected_phase"))
    }

    func testShouldStartDebugSessionOnAutoActivateOnlyWhenIdleOrResolved() {
        XCTAssertTrue(shouldStartDebugSessionOnAutoActivate(currentPhase: .idle))
        XCTAssertTrue(shouldStartDebugSessionOnAutoActivate(currentPhase: .resolved))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .describing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .reproducing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .fixing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .instrumenting))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .verifying))
    }

    func testResolveShouldRunPlanInlineOneShotBehaviorForSlashPlan() {
        let firstSend = resolveShouldRunPlanInline(
            forcePlanInline: true,
            coderMode: .agent,
            planToggleEnabled: false
        )
        XCTAssertTrue(firstSend)

        let secondSend = resolveShouldRunPlanInline(
            forcePlanInline: false,
            coderMode: .agent,
            planToggleEnabled: false
        )
        XCTAssertFalse(secondSend)
    }

    func testResolveShouldRunPlanInlineRespectsManualToggle() {
        XCTAssertTrue(
            resolveShouldRunPlanInline(
                forcePlanInline: false,
                coderMode: .agent,
                planToggleEnabled: true
            )
        )
        XCTAssertFalse(
            resolveShouldRunPlanInline(
                forcePlanInline: false,
                coderMode: .plan,
                planToggleEnabled: true
            )
        )
    }

    func testNonSwarmModesShowComposerAndFooter() {
        XCTAssertFalse(shouldShowSwarmViewOnly(for: .agent))
        XCTAssertTrue(shouldShowComposer(for: .agent))
        XCTAssertTrue(shouldShowUsageFooter(for: .agent))
    }

    func testUsageFooterVisibleInEveryMode() {
        for mode in CoderMode.allCases {
            XCTAssertTrue(shouldShowUsageFooter(for: mode), "Footer usage should be visible in \\(mode.rawValue)")
        }
    }

    func testPlanContextDoesNotActivateFromGenericTaskState() {
        let currentConversationId = UUID()
        let streamConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: streamConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: false,
            showPlanPanel: false,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotActivateFromPersistedPlanBoardOnly() {
        let currentConversationId = UUID()
        let streamConversationId = currentConversationId
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: streamConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: true,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: false,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotActivateFromPanelOpenOnly() {
        let currentConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: currentConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: true,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: true,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotLeakToDifferentStreamConversationWhenInlinePlanActive() {
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: true,
            hasActivePlanFlowPhase: true,
            streamConversationId: otherConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: true,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextStillActivatesForExplicitActiveBuildConversation() {
        let currentConversationId = UUID()
        let buildConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: buildConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: false,
            showPlanPanel: false,
            activeBuildPlanConversationId: buildConversationId
        )
        XCTAssertTrue(result)
    }

    func testShouldMutatePlanStateOnlyForCurrentConversation() {
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        XCTAssertTrue(
            shouldMutatePlanState(
                targetConversationId: currentConversationId,
                currentConversationId: currentConversationId
            )
        )
        XCTAssertFalse(
            shouldMutatePlanState(
                targetConversationId: otherConversationId,
                currentConversationId: currentConversationId
            )
        )
        XCTAssertFalse(
            shouldMutatePlanState(
                targetConversationId: otherConversationId,
                currentConversationId: nil
            )
        )
    }

    func testRoutePlanStreamOnlyForPlanContextOrActiveBuildConversations() {
        let streamConversationId = UUID()
        let activeBuildPlanConversationId = UUID()
        let activeBuildAgentConversationId = UUID()

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: streamConversationId,
                hasActivePlanContext: true,
                phase: .idle,
                activeBuildPlanConversationId: nil,
                activeBuildAgentConversationId: nil
            )
        )

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: activeBuildAgentConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: false,
                streamConversationId: activeBuildAgentConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )

        XCTAssertFalse(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: streamConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )
    }

    func testShouldClearPlanCanonicalTodosOnNewTurnPolicy() {
        XCTAssertTrue(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .building,
                hasActivePlanBuildTask: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: true
            )
        )
    }

    func testPreflightFailureResetPolicyAffectsOnlyInProgressPlanDiscoveryPhases() {
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .analyzing
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .questioning
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .generating
            )
        )
        XCTAssertFalse(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .readyToBuild
            )
        )
        XCTAssertFalse(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: false,
                phase: .analyzing
            )
        )
    }

    func testPlanToggleDeactivationPolicyBlocksOnlyInProgressPhases() {
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .analyzing))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .questioning))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .generating))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .building))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .idle))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .proposalReady))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .readyToBuild))
    }

    func testPanelCloseDisablesToggleOnlyWhenNoActivePlanContext() {
        XCTAssertTrue(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .idle,
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .building,
                planningState: .idle,
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .awaitingClarification(questions: "## Questions\n1. X?"),
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .idle,
                coderMode: .plan
            )
        )
    }

    func testShouldHidePlanMarkdownInChatRequiresPanelRouting() {
        XCTAssertFalse(
            shouldHidePlanMarkdownInChat(
                shouldRoutePlanStreamToPanel: false,
                coderMode: .agent,
                shouldRunPlanInline: false,
                fullLooksLikePlanPayload: true,
                shouldHidePlanMarkdownForBuild: false,
                hasActivePlanContext: false
            )
        )
    }

    func testShouldHidePlanMarkdownInChatWhenRoutedAndPlanSignalsPresent() {
        XCTAssertTrue(
            shouldHidePlanMarkdownInChat(
                shouldRoutePlanStreamToPanel: true,
                coderMode: .agent,
                shouldRunPlanInline: false,
                fullLooksLikePlanPayload: true,
                shouldHidePlanMarkdownForBuild: false,
                hasActivePlanContext: false
            )
        )
    }

    func testResolvePlanStepTargetConversationIdPrefersEventConversation() {
        let eventConversationId = UUID()
        let buildConversationId = UUID()
        let activeTaskConversationId = UUID()
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: eventConversationId,
                activeBuildPlanConversationId: buildConversationId,
                activeTaskConversationId: activeTaskConversationId
            ),
            eventConversationId
        )
    }

    func testResolvePlanStepTargetConversationIdFallsBackToBuildThenActiveTask() {
        let buildConversationId = UUID()
        let activeTaskConversationId = UUID()
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: buildConversationId,
                activeTaskConversationId: activeTaskConversationId
            ),
            buildConversationId
        )
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: nil,
                activeTaskConversationId: activeTaskConversationId
            ),
            activeTaskConversationId
        )
    }

    func testShouldResetTaskActivityStoreBeforeStartingTurnOnlyWithoutOtherActiveTasks() {
        let targetConversationId = UUID()
        XCTAssertTrue(
            shouldResetTaskActivityStoreBeforeStartingTurn(
                activeTaskConversationIds: Set([targetConversationId]),
                targetConversationId: targetConversationId
            )
        )
        XCTAssertFalse(
            shouldResetTaskActivityStoreBeforeStartingTurn(
                activeTaskConversationIds: Set([targetConversationId, UUID()]),
                targetConversationId: targetConversationId
            )
        )
    }
}
