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

    func testExpectedEntityVersionMismatchThrowsConflict() async throws {
        let coordinator = VerifiedFindingsCommandCoordinator()
        let meta = VerifiedCommandMeta(
            commandId: "command-2",
            entityId: "finding-2",
            issuedBy: "tester",
            issuedFrom: .mcp,
            requestFingerprint: "verify|finding-2",
            expectedEntityVersion: 3
        )

        do {
            _ = try await coordinator.execute(
                meta: meta,
                successSummary: "done",
                currentEntityVersion: { 2 }
            ) {}
            XCTFail("Expected a version conflict")
        } catch let error as VerifiedFindingsCommandError {
            XCTAssertEqual(error, .versionConflict(expected: 3, actual: 2))
        }
    }

    func testMatchingExpectedEntityVersionAllowsExecution() async throws {
        let coordinator = VerifiedFindingsCommandCoordinator()
        let meta = VerifiedCommandMeta(
            commandId: "command-3",
            entityId: "finding-3",
            issuedBy: "tester",
            issuedFrom: .mcp,
            requestFingerprint: "apply|finding-3",
            expectedEntityVersion: 5
        )
        let counter = LockedCounter()

        let result = try await coordinator.execute(
            meta: meta,
            successSummary: "applied",
            currentEntityVersion: { 5 }
        ) {
            await counter.increment()
        }
        let finalValue = await counter.value

        XCTAssertEqual(result, .executed(summary: "applied"))
        XCTAssertEqual(finalValue, 1)
    }
}

private actor LockedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
