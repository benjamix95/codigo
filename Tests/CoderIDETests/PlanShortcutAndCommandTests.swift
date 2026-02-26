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

    func testEvaluateShiftTabPlanShortcutFirstPressOnlyHighlightsPlan() {
        let now = Date()
        let result = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: nil,
            currentInputText: "fix parser"
        )

        XCTAssertEqual(result.nextInputText, "fix parser")
        XCTAssertFalse(result.shouldFocusInput)
        XCTAssertTrue(result.shouldHighlightPlanToggle)
        XCTAssertNotNil(result.nextPrimedUntil)
        XCTAssertTrue(result.nextPrimedUntil! > now)
    }

    func testEvaluateShiftTabPlanShortcutSecondPressPrependsPlanCommand() {
        let now = Date()
        let result = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: now.addingTimeInterval(1.0),
            currentInputText: "analyze the refactor"
        )

        XCTAssertEqual(result.nextInputText, "/plan analyze the refactor")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertNil(result.nextPrimedUntil)
    }

    func testEvaluateShiftTabPlanShortcutSecondPressWithEmptyInputSetsPlanOnly() {
        let now = Date()
        let result = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: now.addingTimeInterval(1.0),
            currentInputText: "   "
        )

        XCTAssertEqual(result.nextInputText, "/plan ")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertNil(result.nextPrimedUntil)
    }

    func testEvaluateShiftTabPlanShortcutSecondPressKeepsExistingPlanPrefix() {
        let now = Date()
        let result = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: now.addingTimeInterval(1.0),
            currentInputText: "/plan roadmap fix"
        )

        XCTAssertEqual(result.nextInputText, "/plan roadmap fix")
        XCTAssertTrue(result.shouldFocusInput)
        XCTAssertFalse(result.shouldHighlightPlanToggle)
        XCTAssertNil(result.nextPrimedUntil)
    }

    func testEvaluateShiftTabPlanShortcutAfterExpiryHighlightsAgain() {
        let now = Date()
        let result = evaluateShiftTabPlanShortcut(
            now: now,
            primedUntil: now.addingTimeInterval(-0.1),
            currentInputText: "nuovo task"
        )

        XCTAssertEqual(result.nextInputText, "nuovo task")
        XCTAssertFalse(result.shouldFocusInput)
        XCTAssertTrue(result.shouldHighlightPlanToggle)
        XCTAssertNotNil(result.nextPrimedUntil)
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
        XCTAssertFalse(shouldAutoOpenPlanPanel(trigger: .flowStarted))
        XCTAssertTrue(shouldAutoOpenPlanPanel(trigger: .awaitingClarification))
        XCTAssertTrue(shouldAutoOpenPlanPanel(trigger: .awaitingChoice))
    }

    func testShouldEnableTaskPanelForOperationalModes() {
        XCTAssertTrue(shouldEnableTaskPanelForMode(.agent))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.plan))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.codeReviewMultiSwarm))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.agentSwarm))
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

    func testSwarmModeIsViewOnlyForComposerAndUsageFooterStillVisible() {
        // Swarm mode now uses a sidebar panel instead of replacing the main view,
        // so the composer and footer are always visible.
        XCTAssertFalse(shouldShowSwarmViewOnly(for: .agentSwarm))
        XCTAssertTrue(shouldShowComposer(for: .agentSwarm))
        XCTAssertTrue(shouldShowUsageFooter(for: .agentSwarm))
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
}
