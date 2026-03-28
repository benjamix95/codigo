import XCTest
@testable import CoderEngine

final class AnalysisToolSelectionPolicyTests: XCTestCase {

    // MARK: - Selection Mode Tests

    func testFullAnalysisIncludesPerformanceTools() {
        let (mode, tools) = AnalysisToolSelectionPolicy.resolveToolSelection(
            userPrompt: "analizza l'app"
        )
        XCTAssertEqual(mode, .full)
        for perfTool in ReviewAuditToolName.performanceTools {
            XCTAssertTrue(tools.contains(perfTool), "\(perfTool) deve essere incluso nell'analisi completa")
        }
    }

    func testExplicitToolNameOverridesPolicy() {
        let (mode, tools) = AnalysisToolSelectionPolicy.resolveToolSelection(
            userPrompt: "analizza l'app",
            explicitToolName: ReviewAuditToolName.perfBottlenecks
        )
        XCTAssertEqual(mode, .explicit)
        XCTAssertEqual(tools, [ReviewAuditToolName.perfBottlenecks])
    }

    func testPerformanceKeywordSelectsPerformanceOnly() {
        let (mode, tools) = AnalysisToolSelectionPolicy.resolveToolSelection(
            userPrompt: "controlla le performance dell'app"
        )
        XCTAssertEqual(mode, .performanceOnly)
        XCTAssertEqual(Set(tools), Set(ReviewAuditToolName.performanceTools))
    }

    func testSecurityRequestExcludesPerformance() {
        let (mode, tools) = AnalysisToolSelectionPolicy.resolveToolSelection(
            userPrompt: "cerca vulnerabilità di sicurezza"
        )
        XCTAssertEqual(mode, .securityAndBugs)
        for perfTool in ReviewAuditToolName.performanceTools {
            XCTAssertFalse(tools.contains(perfTool), "\(perfTool) non deve essere in modalità securityAndBugs")
        }
    }

    func testDefaultPromptIncludesPerformance() {
        let (mode, _) = AnalysisToolSelectionPolicy.resolveToolSelection(
            userPrompt: "ciao come stai"
        )
        XCTAssertEqual(mode, .full, "Prompt generico deve defaultare ad analisi completa")
    }

    // MARK: - shouldIncludePerformanceTools

    func testShouldIncludePerformanceToolsForFull() {
        XCTAssertTrue(AnalysisToolSelectionPolicy.shouldIncludePerformanceTools(mode: .full))
    }

    func testShouldIncludePerformanceToolsForPerformanceOnly() {
        XCTAssertTrue(AnalysisToolSelectionPolicy.shouldIncludePerformanceTools(mode: .performanceOnly))
    }

    func testShouldNotIncludePerformanceToolsForSecurityAndBugs() {
        XCTAssertFalse(AnalysisToolSelectionPolicy.shouldIncludePerformanceTools(mode: .securityAndBugs))
    }

    func testShouldNotIncludePerformanceToolsForExplicit() {
        XCTAssertFalse(AnalysisToolSelectionPolicy.shouldIncludePerformanceTools(mode: .explicit))
    }

    // MARK: - Profile Resolution

    func testProfileResolvesToPerformanceDeep() {
        let profile = AnalysisToolSelectionPolicy.resolveProfile(
            userPrompt: "benchmark delle performance"
        )
        XCTAssertEqual(profile, .performanceDeep)
    }

    func testProfileResolvesToIOSPreflight() {
        let profile = AnalysisToolSelectionPolicy.resolveProfile(
            userPrompt: "prepara per iOS app store"
        )
        XCTAssertEqual(profile, .iosPreflight)
    }

    func testExplicitProfileOverrides() {
        let profile = AnalysisToolSelectionPolicy.resolveProfile(
            userPrompt: "analizza performance",
            explicitProfile: .releaseGate
        )
        XCTAssertEqual(profile, .releaseGate)
    }
}
