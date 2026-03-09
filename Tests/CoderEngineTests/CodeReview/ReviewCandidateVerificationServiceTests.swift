import Foundation
import XCTest
@testable import CoderEngine

final class ReviewCandidateVerificationServiceTests: XCTestCase {
    private var workspaceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-candidate-verifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspaceURL)
        workspaceURL = nil
        try super.tearDownWithError()
    }

    func testMissingLineContextStaysInconclusiveEvenWhenEvidenceExistsInFile() throws {
        let fileURL = workspaceURL.appendingPathComponent("Sample.swift")
        try """
        let token = "SECRET_MATCH"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Sample.swift",
            lineNumber: nil,
            message: "Potential issue",
            evidence: "SECRET_MATCH"
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Sample.swift"]
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.method, "file_evidence_search")
    }

    func testSemanticRiskHeuristicDoesNotPromoteToVerified() throws {
        let fileURL = workspaceURL.appendingPathComponent("Risky.swift")
        try """
        let value = try! expensiveCall()
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .critical,
            category: .regression,
            origin: .reviewer,
            filePath: "Risky.swift",
            lineNumber: 1,
            message: "force-try can crash the flow",
            evidence: nil
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Risky.swift"]
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.method, "semantic_risk_match")
    }

    func testExactLineEvidenceStillPromotesToVerified() throws {
        let fileURL = workspaceURL.appendingPathComponent("Exact.swift")
        try """
        let apiKey = "abc"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .warning,
            category: .security,
            origin: .reviewer,
            filePath: "Exact.swift",
            lineNumber: 1,
            message: "Secret in source",
            evidence: #"apiKey = "abc""#
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Exact.swift"]
        )

        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.method, "line_evidence_match")
    }
}
