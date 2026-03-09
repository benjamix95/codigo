import XCTest
@testable import CoderEngine

final class CodeReviewFindingTests: XCTestCase {

    // MARK: - Init

    func testDefaultInit() {
        let finding = CodeReviewFinding(
            severity: .warning,
            category: .correctness,
            filePath: "test.swift",
            message: "Potential nil dereference"
        )

        XCTAssertFalse(finding.id.isEmpty)
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.category, .correctness)
        XCTAssertEqual(finding.origin, .reviewer)
        XCTAssertEqual(finding.filePath, "test.swift")
        XCTAssertNil(finding.lineNumber)
        XCTAssertNil(finding.endLineNumber)
        XCTAssertEqual(finding.message, "Potential nil dereference")
        XCTAssertNil(finding.suggestedFix)
        XCTAssertEqual(finding.status, .open)
        XCTAssertTrue(finding.comments.isEmpty)
    }

    func testFullInit() {
        let finding = CodeReviewFinding(
            id: "custom-id",
            severity: .critical,
            category: .security,
            origin: .securityAuditor,
            filePath: "auth.swift",
            lineNumber: 10,
            endLineNumber: 15,
            message: "SQL injection",
            suggestedFix: "Use parameterized queries",
            expectedInvariant: "Only admins may execute this path.",
            reproOrReasoning: "Request reaches the sink before authz is checked.",
            status: .open,
            comments: [FindingComment(content: "Urgent")]
        )

        XCTAssertEqual(finding.id, "custom-id")
        XCTAssertEqual(finding.severity, .critical)
        XCTAssertEqual(finding.origin, .securityAuditor)
        XCTAssertEqual(finding.lineNumber, 10)
        XCTAssertEqual(finding.endLineNumber, 15)
        XCTAssertEqual(finding.suggestedFix, "Use parameterized queries")
        XCTAssertEqual(finding.expectedInvariant, "Only admins may execute this path.")
        XCTAssertEqual(finding.reproOrReasoning, "Request reaches the sink before authz is checked.")
        XCTAssertEqual(finding.comments.count, 1)
    }

    // MARK: - Severity Sort Order

    func testSeveritySortOrder() {
        XCTAssertLessThan(FindingSeverity.critical.sortOrder, FindingSeverity.warning.sortOrder)
        XCTAssertLessThan(FindingSeverity.warning.sortOrder, FindingSeverity.suggestion.sortOrder)
        XCTAssertLessThan(FindingSeverity.suggestion.sortOrder, FindingSeverity.info.sortOrder)
    }

    // MARK: - Payload

    func testToPayload() {
        let finding = CodeReviewFinding(
            id: "f1",
            severity: .warning,
            category: .performance,
            filePath: "perf.swift",
            lineNumber: 42,
            message: "N+1 query",
            suggestedFix: "Use batch fetch"
        )

        let payload = finding.toPayload()
        XCTAssertEqual(payload["id"], "f1")
        XCTAssertEqual(payload["severity"], "warning")
        XCTAssertEqual(payload["category"], "performance")
        XCTAssertEqual(payload["origin"], "reviewer")
        XCTAssertEqual(payload["file_path"], "perf.swift")
        XCTAssertEqual(payload["line_number"], "42")
        XCTAssertEqual(payload["message"], "N+1 query")
        XCTAssertEqual(payload["suggested_fix"], "Use batch fetch")
        XCTAssertEqual(payload["status"], "open")
    }

    func testFromCandidatePreservesVerificationContextAndRemediation() {
        let candidate = ReviewCandidate(
            id: "candidate-1",
            severity: .critical,
            category: .security,
            origin: .securityAuditor,
            filePath: "Sources/Auth/AdminGuard.swift",
            lineNumber: 18,
            message: "Admin action lacks authorization guard",
            evidence: "Route reaches admin action without role check",
            expectedInvariant: "Only admins can execute the action",
            reproOrReasoning: "Add a role guard before invoking the action",
            confidence: 0.97,
            sourceTool: "security-auditor",
            signalType: .pattern,
            verificationStatus: .verified,
            verificationMethod: "line_evidence_match",
            verificationReport: "Verified on the concrete guard line.",
            verifiedAt: Date()
        )

        let finding = CodeReviewFinding.fromCandidate(candidate)

        XCTAssertEqual(finding.suggestedFix, "Add a role guard before invoking the action")
        XCTAssertEqual(finding.expectedInvariant, "Only admins can execute the action")
        XCTAssertEqual(finding.reproOrReasoning, "Add a role guard before invoking the action")
        XCTAssertEqual(finding.verificationReport, "Verified on the concrete guard line.")
    }

    func testToPayloadOmitsNilFields() {
        let finding = CodeReviewFinding(
            severity: .info,
            category: .other,
            filePath: "file.swift",
            message: "Note"
        )

        let payload = finding.toPayload()
        XCTAssertNil(payload["line_number"])
        XCTAssertNil(payload["end_line_number"])
        XCTAssertNil(payload["suggested_fix"])
        XCTAssertNil(payload["comment_count"])
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = CodeReviewFinding(
            id: "roundtrip",
            severity: .suggestion,
            category: .maintainability,
            origin: .bugHunter,
            filePath: "style.swift",
            lineNumber: 5,
            message: "Use camelCase",
            suggestedFix: "Rename to camelCase",
            expectedInvariant: "Names should stay stable and readable.",
            reproOrReasoning: "The current API leaks inconsistent naming.",
            comments: [FindingComment(content: "Agreed")]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodeReviewFinding.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.severity, original.severity)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.origin, original.origin)
        XCTAssertEqual(decoded.filePath, original.filePath)
        XCTAssertEqual(decoded.lineNumber, original.lineNumber)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.suggestedFix, original.suggestedFix)
        XCTAssertEqual(decoded.expectedInvariant, original.expectedInvariant)
        XCTAssertEqual(decoded.reproOrReasoning, original.reproOrReasoning)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.comments.count, 1)
    }

    func testLegacyCategoryDecodeMapsToCurrentCategory() throws {
        let json = """
        {
          "id": "legacy",
          "severity": "warning",
          "category": "bug",
          "filePath": "legacy.swift",
          "message": "legacy finding",
          "status": "open",
          "comments": [],
          "createdAt": "2026-03-07T18:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let finding = try decoder.decode(CodeReviewFinding.self, from: Data(json.utf8))
        XCTAssertEqual(finding.category, .correctness)
        XCTAssertEqual(finding.origin, .reviewer)
    }

    // MARK: - SessionConfig Clamping

    func testSessionConfigClamping() {
        let config = SessionConfig(maxWorkers: 100, maxRounds: 0)
        XCTAssertEqual(config.maxWorkers, 12)
        XCTAssertEqual(config.maxRounds, 1)
    }

    func testSessionConfigDefaults() {
        let config = SessionConfig.default
        XCTAssertEqual(config.maxWorkers, 6)
        XCTAssertEqual(config.maxRounds, 3)
        XCTAssertEqual(config.analysisBackend, "codex")
        XCTAssertEqual(config.executionBackend, "codex")
    }
}
