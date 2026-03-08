import XCTest
@testable import CoderEngine

extension CodeReviewSessionStateTests {
    func testCompleteClearsCurrentJobId() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])

        await state.start(scope: scope)
        await state.setCurrentJobId("job-123")
        await state.complete()

        let snapshot = await state.snapshot()
        XCTAssertNil(snapshot.currentJobId)
        XCTAssertEqual(snapshot.activeWorkerCount, 0)
    }

    func testFailClearsCurrentJobId() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])

        await state.start(scope: scope)
        await state.setCurrentJobId("job-123")
        await state.fail(error: "boom")

        let snapshot = await state.snapshot()
        XCTAssertNil(snapshot.currentJobId)
        XCTAssertEqual(snapshot.activeWorkerCount, 0)
    }
}
