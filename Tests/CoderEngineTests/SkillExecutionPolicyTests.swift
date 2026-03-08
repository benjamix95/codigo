import Foundation
import XCTest
@testable import CoderEngine

final class SkillExecutionPolicyTests: XCTestCase {
    func testBuildPromptAddsNoNestedSkillOrSubagentConstraints() {
        let prompt = SkillExecutionPolicy.buildPrompt(
            skillName: "code-review",
            skillContent: "Review the repository carefully.",
            userTask: "Find regressions."
        )

        XCTAssertTrue(prompt.contains("Do not call the `skill` tool again"))
        XCTAssertTrue(prompt.contains("Do not invoke `subagent_*`"))
        XCTAssertTrue(prompt.contains("orchestration tools"))
        XCTAssertTrue(prompt.contains("**Task:** Find regressions."))
    }

    func testMaxExecutionSecondsUsesPositiveEnvironmentOverride() {
        withEnvironmentVariable("CODEX_SKILL_TIMEOUT_SECONDS", value: "7") {
            XCTAssertEqual(SkillExecutionPolicy.maxExecutionSeconds, 7)
        }
    }

    func testMaxExecutionSecondsIgnoresInvalidEnvironmentOverride() {
        withEnvironmentVariable("CODEX_SKILL_TIMEOUT_SECONDS", value: "0") {
            XCTAssertEqual(SkillExecutionPolicy.maxExecutionSeconds, 20)
        }
        withEnvironmentVariable("CODEX_SKILL_TIMEOUT_SECONDS", value: "invalid") {
            XCTAssertEqual(SkillExecutionPolicy.maxExecutionSeconds, 20)
        }
    }

    private func withEnvironmentVariable(_ key: String, value: String, operation: () -> Void) {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        operation()
    }
}
