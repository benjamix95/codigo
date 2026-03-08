import XCTest
@testable import CoderEngine

final class CodeReviewAuditAdvancedTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-advanced-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    func testSecurityDataflowDetectsSourceSinkPattern() throws {
        let file = tempDir.appendingPathComponent("Service.swift")
        try """
        let input = request.query["cmd"]
        runProcess(input, shell: true)
        """.write(to: file, atomically: true, encoding: .utf8)

        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.securityDataflow,
            scopeFiles: ["Service.swift"],
            workspacePath: tempDir
        )

        XCTAssertEqual(result.toolName, ReviewAuditToolName.securityDataflow)
        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertEqual(result.payload.findings.first?.signalType, "semantic")
    }

    func testBugTestImpactFlagsPublicSymbolsWithoutTests() throws {
        let file = tempDir.appendingPathComponent("API.swift")
        try """
        public struct CheckoutService {
            public func submitOrder() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.bugTestImpact,
            scopeFiles: ["API.swift"],
            workspacePath: tempDir
        )

        XCTAssertEqual(result.toolName, ReviewAuditToolName.bugTestImpact)
        XCTAssertEqual(result.findings.first?.category, .tests)
    }

    func testCorrelateResultsBuildsClusters() throws {
        let findings = [
            CodeReviewFinding(
                id: "f1",
                severity: .warning,
                category: .security,
                origin: .securityAuditor,
                filePath: "A.swift",
                lineNumber: 10,
                message: "Unsafe sink found."
            ),
            CodeReviewFinding(
                id: "f2",
                severity: .warning,
                category: .security,
                origin: .securityAuditor,
                filePath: "B.swift",
                lineNumber: 12,
                message: "Unsafe sink found."
            ),
        ]
        let correlated = CodeReviewAuditService.correlateResults(
            [
                ReviewAuditToolResult(
                    toolName: ReviewAuditToolName.securityPatterns,
                    findings: findings,
                    durationMs: 1,
                    coverageAvailable: true,
                    summary: "test"
                ),
            ],
            summaryPrefix: "test"
        )

        XCTAssertEqual(correlated.clusters.count, 1)
        XCTAssertEqual(correlated.findings.count, 2)
    }

    func testRunProfileSecurityDeepIncludesAdvancedSecurityTools() throws {
        let results = CodeReviewAuditService.runProfile(
            named: .securityDeep,
            scopeFiles: [],
            workspacePath: tempDir
        )

        let names = Set(results.map(\.toolName))
        XCTAssertTrue(names.contains(ReviewAuditToolName.securityDataflow))
        XCTAssertTrue(names.contains(ReviewAuditToolName.securitySupplyChain))
    }
}
