import XCTest
@testable import CoderEngine

final class SystemPromptsTests: XCTestCase {
    func testOptimizedConfigContainsExpectedSections() {
        let prompt = SystemPrompts.optimized(
            config: PromptConfig(
                profile: .seniorEngineer,
                domain: .iosSwift,
                safetyMode: .authorizedSecurity,
                verbosity: .audit,
                toolAggressiveness: .aggressive,
                requiresFinalOutcome: true
            )
        )

        XCTAssertTrue(prompt.contains("Persona: Senior Engineer"))
        XCTAssertTrue(prompt.contains("Domain: iOS/Swift"))
        XCTAssertTrue(prompt.contains("Security policy (red+blue authorized)"))
        XCTAssertTrue(prompt.contains("Output style — audit"))
        XCTAssertTrue(prompt.contains("Final outcome"))
    }

    func testOptimizedProfileBackwardCompatibility() {
        let prompt = SystemPrompts.optimized(profile: .planner)
        XCTAssertTrue(prompt.contains("Planner mode"))
    }

    func testCursorDefaultContainsCoreSections() {
        let prompt = SystemPrompts.cursorDefault
        XCTAssertTrue(prompt.contains("Solo Code"))
        XCTAssertTrue(prompt.contains("Core rules"))
        XCTAssertTrue(prompt.contains("Completion contract"))
        XCTAssertTrue(prompt.contains("Execution discipline"))
        XCTAssertTrue(prompt.contains("Tool usage policy"))
        XCTAssertTrue(prompt.contains("Planning policy"))
        XCTAssertTrue(prompt.contains("Finisher mode"))
    }

    func testTaskCompletionStrictContainsIdentity() {
        let prompt = SystemPrompts.taskCompletionStrict
        XCTAssertTrue(prompt.contains("Solo Code"))
        XCTAssertTrue(prompt.contains("str_replace"))
    }

    func testTaskCompletionStrictContainsSelectiveStagingWorkflow() {
        let prompt = SystemPrompts.taskCompletionStrict
        XCTAssertTrue(prompt.contains("Mandatory selective staging and commit workflow"))
        XCTAssertTrue(prompt.contains("Agent + Code Review + Swarm"))
        XCTAssertTrue(prompt.contains("git add -p"))
        XCTAssertTrue(prompt.contains("git apply --cached"))
        XCTAssertTrue(prompt.contains("git diff --cached"))
        XCTAssertTrue(prompt.contains("git diff --cached --stat"))
    }

    func testAllProfilesCompile() {
        let profiles: [PromptProfile] = [
            .cursorDefault, .planner, .implementer, .debugger, .reviewer, .finisher,
            .seniorEngineer, .staffArchitect, .principalReviewer,
            .incidentResponder, .securityRedBlueAuthorized
        ]
        for profile in profiles {
            let prompt = SystemPrompts.optimized(profile: profile)
            XCTAssertFalse(prompt.isEmpty, "Profile \(profile) should produce non-empty prompt")
            XCTAssertTrue(prompt.count > 50, "Profile \(profile) prompt too short: \(prompt.count)")
        }
    }

    func testAllDomainsAreEnglish() {
        let prompt = SystemPrompts.optimized(
            config: PromptConfig(
                profile: .cursorDefault,
                domain: .iosSwift,
                safetyMode: .standard,
                verbosity: .normal
            )
        )
        XCTAssertTrue(prompt.contains("Domain: iOS/Swift"))
        XCTAssertFalse(prompt.contains("Dominio"))
    }

    func testAllModesAreEnglish() {
        let planner = SystemPrompts.planner
        XCTAssertTrue(planner.contains("Planner mode"))
        XCTAssertFalse(planner.contains("Modalità"))

        let implementer = SystemPrompts.implementer
        XCTAssertTrue(implementer.contains("Implementer mode"))

        let debugger = SystemPrompts.debugger
        XCTAssertTrue(debugger.contains("Debugger mode"))

        let reviewer = SystemPrompts.reviewer
        XCTAssertTrue(reviewer.contains("Reviewer mode"))
    }

    func testDebuggerModeMentionsSessionGatingAndCanonicalDebugTools() {
        let debugger = SystemPrompts.debugger
        XCTAssertTrue(debugger.contains("Tool gating"))
        XCTAssertTrue(debugger.contains("coderide_debug_set_phase"))
        XCTAssertTrue(debugger.contains("debug_panel"))
    }
}
