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

    func testBugNilCrashPathsDoesNotFlagGenericNegationOrInequality() throws {
        let file = tempDir.appendingPathComponent("Logic.swift")
        try """
        if value != nil { print("ok") }
        let enabled = !flag
        """.write(to: file, atomically: true, encoding: .utf8)

        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.bugNilCrashPaths,
            scopeFiles: ["Logic.swift"],
            workspacePath: tempDir
        )

        XCTAssertTrue(result.findings.isEmpty)
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

    // MARK: - durationMs is computed (not hardcoded to 0)

    func testRunToolDurationMsIsPositive() throws {
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.securitySecrets,
            scopeFiles: [],
            workspacePath: tempDir
        )

        XCTAssertGreaterThanOrEqual(result.durationMs, 1,
            "durationMs must be computed from elapsed time, not hardcoded to 0")
    }

    // MARK: - verificationHints never contain empty strings

    func testVerificationHintsContainNoEmptyStrings() throws {
        let file = tempDir.appendingPathComponent("Dummy.swift")
        try "let x = 1".write(to: file, atomically: true, encoding: .utf8)

        let toolNames = [
            ReviewAuditToolName.securityDataflow,
            ReviewAuditToolName.securityAuthz,
            ReviewAuditToolName.securityCrypto,
            ReviewAuditToolName.bugNilCrashPaths,
            ReviewAuditToolName.bugConcurrency,
        ]

        for name in toolNames {
            let result = CodeReviewAuditService.runTool(
                named: name,
                scopeFiles: ["Dummy.swift"],
                workspacePath: tempDir
            )
            let empties = result.verificationHints.filter { $0.isEmpty }
            XCTAssertTrue(empties.isEmpty,
                "\(name): verificationHints should not contain empty strings, got \(result.verificationHints)")
        }
    }

    // MARK: - lineNumber preserved through finding pipeline

    func testFindingLineNumberPreservedInDeduplicate() throws {
        let findings = [
            CodeReviewFinding(
                id: "ln1",
                severity: .warning,
                category: .correctness,
                origin: .auditTool,
                filePath: "File.swift",
                lineNumber: 42,
                message: "Potential nil crash"
            ),
            CodeReviewFinding(
                id: "ln2",
                severity: .warning,
                category: .correctness,
                origin: .auditTool,
                filePath: "File.swift",
                lineNumber: 99,
                message: "Another issue"
            ),
        ]

        let deduped = CodeReviewAuditService.deduplicate(findings)
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped[0].lineNumber, 42)
        XCTAssertEqual(deduped[1].lineNumber, 99)
    }

    func testFindingFromCandidatePreservesLineNumber() throws {
        let candidate = ReviewCandidate(
            id: "c1",
            severity: .warning,
            category: .security,
            origin: .auditTool,
            filePath: "Service.swift",
            lineNumber: 55,
            endLineNumber: 60,
            message: "Unsafe pattern",
            evidence: "matched regex",
            expectedInvariant: nil,
            reproOrReasoning: nil,
            confidence: 0.9,
            sourceTool: ReviewAuditToolName.securityPatterns,
            signalType: .pattern
        )

        let finding = CodeReviewFinding.fromCandidate(candidate)
        XCTAssertEqual(finding.lineNumber, 55)
        XCTAssertEqual(finding.endLineNumber, 60)
        XCTAssertEqual(finding.filePath, "Service.swift")
    }

    // MARK: - payload preserves lineNumber

    func testPayloadLineNumberMatchesFinding() throws {
        let finding = CodeReviewFinding(
            id: "p1",
            severity: .critical,
            category: .security,
            origin: .securityAuditor,
            filePath: "Auth.swift",
            lineNumber: 77,
            message: "Hardcoded secret"
        )
        let toolResult = ReviewAuditToolResult(
            toolName: ReviewAuditToolName.securitySecrets,
            findings: [finding],
            durationMs: 5,
            coverageAvailable: true,
            summary: "test"
        )

        let payload = toolResult.payload
        XCTAssertEqual(payload.findings.first?.line, 77,
            "Payload line must match finding lineNumber")
    }

    // MARK: - Unsupported tool returns empty result with computed durationMs

    func testUnsupportedToolReturnsEmptyWithPositiveDuration() throws {
        let result = CodeReviewAuditService.runTool(
            named: "nonexistent_tool",
            scopeFiles: [],
            workspacePath: tempDir
        )

        XCTAssertEqual(result.toolName, "nonexistent_tool")
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertFalse(result.coverageAvailable)
        XCTAssertGreaterThanOrEqual(result.durationMs, 1,
            "Even unsupported tools must compute durationMs")
        XCTAssertTrue(result.summary.contains("Unsupported"))
    }

    func testRunOptionalAdapterReturnsUnavailableWhenCommandMissing() throws {
        let report = CodeReviewAuditService.runOptionalAdapter(
            name: "definitely-not-installed-codex-audit-binary",
            arguments: [],
            workspacePath: tempDir
        )

        XCTAssertFalse(report.available)
        XCTAssertEqual(report.output, "")
    }

    func testParseAdapterHintBuildsSecurityFindingWhenMatcherPresent() throws {
        let report = CodeReviewAuditService.ReviewAuditAdapterReport(
            name: "mock-audit",
            available: true,
            output: "Potential token leakage detected in output stream"
        )

        let finding = CodeReviewAuditService.parseAdapterHint(
            report,
            matchers: ["token leakage"],
            findingMessage: "Sensitive token exposed",
            filePath: "Sources/Auth.swift"
        )

        XCTAssertEqual(finding?.category, .security)
        XCTAssertEqual(finding?.origin, .auditTool)
        XCTAssertEqual(finding?.filePath, "Sources/Auth.swift")
        XCTAssertEqual(finding?.sourceTool, "mock-audit")
    }

    // MARK: - explainFinding returns explanation with computed durationMs

    func testExplainFindingReturnsExplanation() throws {
        let result = CodeReviewAuditService.runTool(
            named: ReviewAuditToolName.explainFinding,
            scopeFiles: ["Some context about the finding"],
            workspacePath: tempDir
        )

        XCTAssertEqual(result.toolName, ReviewAuditToolName.explainFinding)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertTrue(result.coverageAvailable)
        XCTAssertGreaterThanOrEqual(result.durationMs, 1)
        XCTAssertEqual(result.summary, "Some context about the finding")
    }

    // MARK: - Deduplicate removes exact duplicates but keeps different lineNumbers

    func testDeduplicateKeepsDifferentLineNumbers() throws {
        let findings = [
            CodeReviewFinding(
                id: "d1", severity: .warning, category: .correctness,
                origin: .auditTool, filePath: "A.swift",
                lineNumber: 10, message: "issue"
            ),
            CodeReviewFinding(
                id: "d2", severity: .warning, category: .correctness,
                origin: .auditTool, filePath: "A.swift",
                lineNumber: 20, message: "issue"
            ),
            CodeReviewFinding(
                id: "d3", severity: .warning, category: .correctness,
                origin: .auditTool, filePath: "A.swift",
                lineNumber: 10, message: "issue"
            ),
        ]

        let deduped = CodeReviewAuditService.deduplicate(findings)
        XCTAssertEqual(deduped.count, 2, "Same file+line+message should deduplicate")
        XCTAssertEqual(deduped[0].lineNumber, 10)
        XCTAssertEqual(deduped[1].lineNumber, 20)
    }

    // MARK: - fromRawTask preserves lineNumber

    func testFromRawTaskPreservesLineNumber() throws {
        let finding = CodeReviewFinding.fromRawTask(
            id: "rt1",
            description: "Null pointer risk",
            files: ["Handler.swift"],
            severity: "warning",
            origin: .auditTool,
            filePath: "Handler.swift",
            lineNumber: 33,
            confidence: 0.85,
            evidence: "force unwrap on optional",
            sourceTool: ReviewAuditToolName.bugNilCrashPaths
        )

        XCTAssertEqual(finding.lineNumber, 33)
        XCTAssertEqual(finding.filePath, "Handler.swift")
        XCTAssertEqual(finding.origin, .auditTool)
        XCTAssertEqual(finding.sourceTool, ReviewAuditToolName.bugNilCrashPaths)
    }

    // MARK: - payload nil lineNumber

    func testPayloadNilLineNumberWhenFindingHasNone() throws {
        let finding = CodeReviewFinding(
            id: "pn1", severity: .suggestion, category: .maintainability,
            origin: .reviewer, filePath: "Style.swift",
            message: "Consider renaming"
        )
        let toolResult = ReviewAuditToolResult(
            toolName: ReviewAuditToolName.securityPatterns,
            findings: [finding], durationMs: 2,
            coverageAvailable: true, summary: "test"
        )

        XCTAssertNil(toolResult.payload.findings.first?.line,
            "Payload line must be nil when finding has no lineNumber")
    }

    // MARK: - durationMs computed for all tool categories

    func testDurationMsComputedForBugTools() throws {
        let file = tempDir.appendingPathComponent("Code.swift")
        try "func test() {}".write(to: file, atomically: true, encoding: .utf8)

        for toolName in [ReviewAuditToolName.bugDiffRisks, ReviewAuditToolName.bugTestGaps, ReviewAuditToolName.bugHotspots] {
            let result = CodeReviewAuditService.runTool(
                named: toolName, scopeFiles: ["Code.swift"], workspacePath: tempDir
            )
            XCTAssertGreaterThanOrEqual(result.durationMs, 1,
                "\(toolName): durationMs must be positive")
        }
    }
}
