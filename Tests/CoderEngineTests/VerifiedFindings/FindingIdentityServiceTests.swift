import XCTest
@testable import CoderEngine

final class FindingIdentityServiceTests: XCTestCase {
    func testExactDuplicatePreferred() {
        let existing = VerifiedFinding(
            id: "existing",
            domain: .bug,
            title: "Crash on nil unwrap",
            summary: "Crash on nil unwrap",
            category: "correctness",
            severity: .high,
            confidence: 0.9,
            status: .candidate,
            filePath: "App.swift",
            lineStart: 10,
            originEntryPoint: .mainChat,
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: .bug,
                filePath: "App.swift",
                category: "correctness",
                title: "Crash on nil unwrap",
                lineStart: 10,
                summary: "Crash on nil unwrap"
            )
        )
        let candidate = existing

        let match = FindingIdentityService.findDuplicate(candidate: candidate, existing: [existing])
        XCTAssertEqual(match?.existingFindingId, "existing")
        XCTAssertEqual(match?.isExactDuplicate, true)
    }
}
