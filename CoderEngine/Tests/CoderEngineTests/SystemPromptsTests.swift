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
        XCTAssertTrue(prompt.contains("Dominio iOS/Swift"))
        XCTAssertTrue(prompt.contains("Security policy (red+blue autorizzato)"))
        XCTAssertTrue(prompt.contains("Stile output audit"))
        XCTAssertTrue(prompt.contains("Final outcome obbligatorio"))
    }

    func testOptimizedProfileBackwardCompatibility() {
        let prompt = SystemPrompts.optimized(profile: .planner)
        XCTAssertTrue(prompt.contains("Modalità Planner"))
    }
}
