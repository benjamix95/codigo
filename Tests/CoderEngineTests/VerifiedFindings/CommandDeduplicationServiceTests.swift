import XCTest
@testable import CoderEngine

final class CommandDeduplicationServiceTests: XCTestCase {
    func testDeduplicatesByCommandIdAndFingerprint() async {
        let service = CommandDeduplicationService()
        let meta = VerifiedCommandMeta(
            commandId: "cmd-1",
            entityId: "finding-1",
            issuedBy: "tester",
            issuedFrom: .panel,
            requestFingerprint: "apply-finding-1"
        )
        _ = await service.record(meta: meta, resultSummary: "applied")

        let sameCommand = await service.existingRecord(for: meta)
        XCTAssertEqual(sameCommand?.resultSummary, "applied")

        let sameFingerprint = VerifiedCommandMeta(
            commandId: "cmd-2",
            entityId: "finding-1",
            issuedBy: "tester",
            issuedFrom: .mainChat,
            requestFingerprint: "apply-finding-1"
        )
        let sameFingerprintRecord = await service.existingRecord(for: sameFingerprint)
        XCTAssertEqual(sameFingerprintRecord?.resultSummary, "applied")
    }
}
