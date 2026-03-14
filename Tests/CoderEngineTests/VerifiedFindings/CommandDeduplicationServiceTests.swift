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

    func testEntityExecutionCoordinatorSerializesSameEntity() async throws {
        let coordinator = EntityExecutionCoordinator()
        let recorder = ExecutionRecorder()

        async let first: Void = coordinator.withExclusiveAccess(entityId: "finding-1") {
            await recorder.append("first-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await recorder.append("first-end")
        }
        async let second: Void = coordinator.withExclusiveAccess(entityId: "finding-1") {
            await recorder.append("second-start")
            await recorder.append("second-end")
        }

        _ = try await (first, second)

        let events = await recorder.events
        XCTAssertEqual(events, ["first-start", "first-end", "second-start", "second-end"])
    }
}

private actor ExecutionRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
