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

    func testApproximateDuplicateUsesSummaryBucketsAndLineTolerance() {
        let existing = VerifiedFinding(
            id: "existing-approx",
            domain: .bug,
            title: "Race condition in stream retry",
            summary: "Late retry emits duplicate terminal event",
            category: "correctness",
            severity: .high,
            confidence: 0.9,
            status: .candidate,
            filePath: "Sources/Runtime/StreamCoordinator.swift",
            lineStart: 24,
            originEntryPoint: .mainChat,
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: .bug,
                filePath: "Sources/Runtime/StreamCoordinator.swift",
                category: "correctness",
                title: "Race condition in stream retry",
                lineStart: 24,
                summary: "Late retry emits duplicate terminal event"
            )
        )
        let candidate = VerifiedFinding(
            id: "candidate-approx",
            domain: .bug,
            title: "Retry path can race with terminal callback",
            summary: "Late retry emits duplicate terminal event",
            category: "correctness",
            severity: .high,
            confidence: 0.88,
            status: .candidate,
            filePath: "Sources/Runtime/StreamCoordinator.swift",
            lineStart: 26,
            originEntryPoint: .mainChat,
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: .bug,
                filePath: "Sources/Runtime/StreamCoordinator.swift",
                category: "correctness",
                title: "Retry path can race with terminal callback",
                lineStart: 26,
                summary: "Late retry emits duplicate terminal event"
            )
        )

        let match = FindingIdentityService.findDuplicate(candidate: candidate, existing: [existing])

        XCTAssertEqual(match?.existingFindingId, "existing-approx")
        XCTAssertEqual(match?.isExactDuplicate, false)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.score ?? 0.0, 0.85, accuracy: 0.0001)
    }

    func testRustIdentityBridgeMatchesSwiftSemanticsWhenLibraryIsAvailable() throws {
        let path = reviewCoreLibraryPath(from: #filePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Libreria review core Rust non disponibile")
        }
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
            ReviewCoreBridge.resetForTests()
        }

        ReviewCoreBridge.resetForTests()
        let existing = VerifiedFinding(
            id: "existing-approx",
            domain: .bug,
            title: "Race condition in stream retry",
            summary: "Late retry emits duplicate terminal event",
            category: "correctness",
            severity: .high,
            confidence: 0.9,
            status: .candidate,
            filePath: "Sources/Runtime/StreamCoordinator.swift",
            lineStart: 24,
            originEntryPoint: .mainChat,
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: .bug,
                filePath: "Sources/Runtime/StreamCoordinator.swift",
                category: "correctness",
                title: "Race condition in stream retry",
                lineStart: 24,
                summary: "Late retry emits duplicate terminal event"
            )
        )
        let candidate = VerifiedFinding(
            id: "candidate-approx",
            domain: .bug,
            title: "Retry path can race with terminal callback",
            summary: "Late retry emits duplicate terminal event",
            category: "correctness",
            severity: .high,
            confidence: 0.88,
            status: .candidate,
            filePath: "Sources/Runtime/StreamCoordinator.swift",
            lineStart: 26,
            originEntryPoint: .mainChat,
            findingFingerprint: FindingIdentityService.fingerprint(
                domain: .bug,
                filePath: "Sources/Runtime/StreamCoordinator.swift",
                category: "correctness",
                title: "Retry path can race with terminal callback",
                lineStart: 26,
                summary: "Late retry emits duplicate terminal event"
            )
        )

        let match = FindingIdentityService.findDuplicate(candidate: candidate, existing: [existing])

        XCTAssertEqual(match?.existingFindingId, "existing-approx")
        XCTAssertEqual(match?.isExactDuplicate, false)
        XCTAssertEqual(match?.score ?? 0.0, 0.85, accuracy: 0.0001)
        XCTAssertTrue(ReviewCoreBridge.loadedState().loaded)
    }
}

private func reviewCoreLibraryPath(from sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    return sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Native/RustCore/build/lib/libsolocode_rust_core.dylib")
        .path
}
