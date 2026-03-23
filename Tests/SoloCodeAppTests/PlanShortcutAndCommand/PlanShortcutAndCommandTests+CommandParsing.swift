import AppKit
import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
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

    func testShouldFallbackToPreferredProviderIsAlwaysDisabled() {
        XCTAssertFalse(
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

}
