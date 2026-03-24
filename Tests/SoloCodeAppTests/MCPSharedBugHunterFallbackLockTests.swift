import XCTest
import Darwin
@testable import CoderEngine

final class MCPSharedBugHunterFallbackLockTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try super.tearDownWithError()
    }

    func testWithBugHunterFileLockFallsBackToLocalLockWhenFileLockFails() {
        let fallbackLock = NSRecursiveLock()
        let lockURL = MCPSharedState.bugHunterDirectoryPath.appendingPathComponent(".lock")

        let result: Int = MCPSharedState.withAdvisoryFileLock(
            label: "BugHunterLockTest",
            lockURL: lockURL,
            createMode: 0o644,
            fallbackLock: fallbackLock,
            ensureLockDirectory: {
                MCPSharedState.ensureBugHunterDirectories()
            },
            acquireLock: {
                .fallback
            },
            body: {
                42
            }
        )

        XCTAssertEqual(result, 42)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: MCPSharedState.bugHunterDirectoryPath.path),
            "Il fallback deve garantire che la directory esista prima di eseguire l'operazione"
        )
    }

    func testWithBugHunterFileLockFallbackSerializesConcurrentAccess() {
        let fallbackLock = NSRecursiveLock()
        let lockURL = MCPSharedState.bugHunterDirectoryPath.appendingPathComponent(".lock")
        let iterations = 50
        let expectation = expectation(description: "fallback lock")
        expectation.expectedFulfillmentCount = iterations
        let queue = DispatchQueue(label: "test.bughunter.fallback", attributes: .concurrent)

        let counterURL = MCPSharedState.bugHunterDirectoryPath
            .appendingPathComponent("fallback_counter.txt")
        try? FileManager.default.createDirectory(
            at: MCPSharedState.bugHunterDirectoryPath,
            withIntermediateDirectories: true
        )
        try? "0".write(to: counterURL, atomically: true, encoding: .utf8)

        for _ in 0..<iterations {
            queue.async {
                MCPSharedState.withAdvisoryFileLock(
                    label: "BugHunterLockTest",
                    lockURL: lockURL,
                    createMode: 0o644,
                    fallbackLock: fallbackLock,
                    ensureLockDirectory: {
                        MCPSharedState.ensureBugHunterDirectories()
                    },
                    acquireLock: {
                        .fallback
                    },
                    body: {
                        let current = (try? String(contentsOf: counterURL, encoding: .utf8))
                            .flatMap(Int.init) ?? 0
                        try? String(current + 1).write(
                            to: counterURL,
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                )
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 15)
        let finalValue = (try? String(contentsOf: counterURL, encoding: .utf8))
            .flatMap(Int.init)
        XCTAssertEqual(finalValue, iterations)
    }
}
