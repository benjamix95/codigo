import XCTest
@testable import CoderEngine

final class VerifiedFindingsCommandCoordinatorTests: XCTestCase {
    func testDuplicateCommandDoesNotReexecuteOperation() async throws {
        let coordinator = VerifiedFindingsCommandCoordinator()
        let meta = VerifiedCommandMeta(
            commandId: "command-1",
            entityId: "finding-1",
            issuedBy: "tester",
            issuedFrom: .mcp,
            requestFingerprint: "apply|finding-1"
        )
        let counter = LockedCounter()

        let first = try await coordinator.execute(meta: meta, successSummary: "done") {
            await counter.increment()
        }
        let second = try await coordinator.execute(meta: meta, successSummary: "done") {
            await counter.increment()
        }
        let finalValue = await counter.value

        XCTAssertEqual(first, .executed(summary: "done"))
        XCTAssertEqual(second, .deduplicated(summary: "done"))
        XCTAssertEqual(finalValue, 1)
    }
}

private actor LockedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
