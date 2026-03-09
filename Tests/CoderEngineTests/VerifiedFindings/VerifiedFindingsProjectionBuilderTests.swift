import XCTest
@testable import CoderEngine

final class VerifiedFindingsProjectionBuilderTests: XCTestCase {
    func testBuildSeparatesCandidateAndVerifiedQueues() {
        let candidate = VerifiedFinding(
            id: "candidate-1",
            domain: .bug,
            title: "Candidate",
            summary: "Candidate",
            category: "correctness",
            severity: .medium,
            confidence: 0.7,
            status: .candidate,
            filePath: "A.swift",
            originEntryPoint: .mainChat,
            findingFingerprint: "fp-a"
        )
        let verified = VerifiedFinding(
            id: "verified-1",
            domain: .bug,
            title: "Verified",
            summary: "Verified",
            category: "correctness",
            severity: .high,
            confidence: 0.95,
            status: .verified,
            filePath: "B.swift",
            originEntryPoint: .reviewChat,
            findingFingerprint: "fp-b",
            possibleDuplicateOf: ["candidate-1"]
        )
        let snapshot = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [
                candidate.id: candidate,
                verified.id: verified,
            ],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: ["verify start", "verify ok"]
        )

        let projection = VerifiedFindingsProjectionBuilder.build(from: snapshot)
        XCTAssertEqual(projection.candidateQueue.map(\.id), ["candidate-1"])
        XCTAssertEqual(projection.verifiedQueue.map(\.id), ["verified-1"])
        XCTAssertEqual(projection.duplicatesCount, 1)
        XCTAssertEqual(projection.traceSnippets.count, 2)
    }
}
