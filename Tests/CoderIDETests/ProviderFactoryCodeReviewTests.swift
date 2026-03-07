import XCTest
import CoderEngine
@testable import CoderIDE

final class ProviderFactoryCodeReviewTests: XCTestCase {
    func testCodeReviewEnabledPhasesUsesSessionAnalysisOnlyOverride() {
        let analysisOnlyConfig = SessionConfig(analysisOnly: true)
        let executionConfig = SessionConfig(analysisOnly: false)

        XCTAssertEqual(
            ProviderFactory.codeReviewEnabledPhases(sessionConfig: analysisOnlyConfig),
            .analysisOnly
        )
        XCTAssertEqual(
            ProviderFactory.codeReviewEnabledPhases(sessionConfig: executionConfig),
            .analysisAndExecution
        )
    }
}
