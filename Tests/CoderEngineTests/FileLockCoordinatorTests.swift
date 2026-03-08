import XCTest
@testable import CoderEngine

final class FileLockCoordinatorTests: XCTestCase {
    func testAcquireLock_prioritizesEarlierOverlappingWaiter() async {
        let coordinator = FileLockCoordinator()
        let files: Set<String> = ["Sources/FeatureA/File.swift"]

        let acquiredInitial = await coordinator.acquireLock(files: files, swarmId: "review-1")
        XCTAssertTrue(acquiredInitial)

        let acquireOrder = AcquireOrderProbe()
        let secondGate = AsyncGate()

        let second = Task {
            if await coordinator.acquireLock(files: files, swarmId: "review-2") {
                await acquireOrder.record("review-2")
                await secondGate.wait()
                await coordinator.releaseLock(files: files, swarmId: "review-2")
            }
        }

        // Ensure review-2 enters the wait queue before review-3.
        try? await Task.sleep(nanoseconds: 80_000_000)

        let third = Task {
            if await coordinator.acquireLock(files: files, swarmId: "review-3") {
                await acquireOrder.record("review-3")
                await coordinator.releaseLock(files: files, swarmId: "review-3")
            }
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        await coordinator.releaseLock(files: files, swarmId: "review-1")

        let gotFirst = await waitUntil(timeoutSeconds: 2) {
            await acquireOrder.count >= 1
        }
        XCTAssertTrue(gotFirst)
        let firstOrderSnapshot = await acquireOrder.snapshot()
        XCTAssertEqual(firstOrderSnapshot, ["review-2"])

        await secondGate.open()

        let gotSecond = await waitUntil(timeoutSeconds: 2) {
            await acquireOrder.count >= 2
        }
        XCTAssertTrue(gotSecond)
        let secondOrderSnapshot = await acquireOrder.snapshot()
        XCTAssertEqual(secondOrderSnapshot, ["review-2", "review-3"])

        _ = await second.value
        _ = await third.value
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }
}

private actor AcquireOrderProbe {
    private(set) var ids: [String] = []

    var count: Int { ids.count }

    func record(_ id: String) {
        ids.append(id)
    }

    func snapshot() -> [String] {
        ids
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: true)
        for continuation in pending {
            continuation.resume()
        }
    }
}
