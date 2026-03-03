import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testDebugTestCheckReturnsFailureWhenTestsFail() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "FailingPkg",
            targets: [
                .target(name: "FailingPkg"),
                .testTarget(name: "FailingPkgTests", dependencies: ["FailingPkg"])
            ]
        )
        """.write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Sources/FailingPkg"), withIntermediateDirectories: true)
        try "public struct Greeter { public static func greet() -> String { \"hi\" } }"
            .write(to: tmp.appendingPathComponent("Sources/FailingPkg/Greeter.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Tests/FailingPkgTests"), withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import FailingPkg

        final class FailingPkgTests: XCTestCase {
            func testAlwaysFails() {
                XCTAssertEqual(Greeter.greet(), "bye")
            }
        }
        """.write(to: tmp.appendingPathComponent("Tests/FailingPkgTests/FailingPkgTests.swift"), atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "debug_test_check",
            args: ["scope": "all", "timeout_ms": "120000"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["overall_status"], "failed")
        XCTAssertEqual(completed?["error_code"], "test_failed")
    }

    func testDebugSessionStartClearsFailingTestScopeCache() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "FailingPkg",
            targets: [
                .target(name: "FailingPkg"),
                .testTarget(name: "FailingPkgTests", dependencies: ["FailingPkg"])
            ]
        )
        """.write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Sources/FailingPkg"), withIntermediateDirectories: true)
        try "public struct Greeter { public static func greet() -> String { \"hi\" } }"
            .write(to: tmp.appendingPathComponent("Sources/FailingPkg/Greeter.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Tests/FailingPkgTests"), withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import FailingPkg

        final class FailingPkgTests: XCTestCase {
            func testAlwaysFails() {
                XCTAssertEqual(Greeter.greet(), "bye")
            }
        }
        """.write(to: tmp.appendingPathComponent("Tests/FailingPkgTests/FailingPkgTests.swift"), atomically: true, encoding: .utf8)

        let (runAll, runAllCtx) = makeCall(
            name: "debug_test_check",
            args: ["scope": "all", "timeout_ms": "120000"],
            workspace: tmp
        )
        _ = await runtime.execute(runAll, context: runAllCtx)

        let (failingBeforeReset, failingBeforeResetCtx) = makeCall(
            name: "debug_test_check",
            args: ["scope": "failing", "timeout_ms": "120000"],
            workspace: tmp
        )
        let beforeResetEvents = await runtime.execute(failingBeforeReset, context: failingBeforeResetCtx)
        let beforeResetPayload = extractLastPayload(beforeResetEvents)
        XCTAssertNotEqual(beforeResetPayload?["overall_status"], "skipped")

        let (startSession, startSessionCtx) = makeCall(
            name: "debug_session",
            args: ["action": "start"],
            workspace: tmp
        )
        _ = await runtime.execute(startSession, context: startSessionCtx)

        let (failingAfterReset, failingAfterResetCtx) = makeCall(
            name: "debug_test_check",
            args: ["scope": "failing", "timeout_ms": "120000"],
            workspace: tmp
        )
        let afterResetEvents = await runtime.execute(failingAfterReset, context: failingAfterResetCtx)
        let afterResetPayload = extractLastPayload(afterResetEvents)

        XCTAssertEqual(afterResetPayload?["status"], "completed")
        XCTAssertEqual(afterResetPayload?["overall_status"], "skipped")
    }

    func testDebugTestCheckReturnsValidationForNonSwiftProject() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "debug_test_check",
            args: ["scope": "all"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue((completed?["detail"] ?? "").contains("Swift Package"))
    }

    func testDebugHypothesizeIsIDBasedForProposeAndUpdate() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (propose, proposeCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "propose",
                "title": "Socket timeout due to DNS",
                "description": "Repro in IPv6 only",
                "status": "proposed"
            ],
            workspace: tmp
        )
        let proposeEvents = await runtime.execute(propose, context: proposeCtx)
        let proposedPayload = extractLastPayload(proposeEvents)
        let hypothesisId = proposedPayload?["hypothesis_id"] ?? ""

        XCTAssertFalse(hypothesisId.isEmpty)
        XCTAssertEqual(proposedPayload?["action"], "propose")

        let (update, updateCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "update",
                "hypothesis_id": hypothesisId,
                "status": "confirmed",
                "evidence": "Observed DNS timeout in runtime logs"
            ],
            workspace: tmp
        )
        let updateEvents = await runtime.execute(update, context: updateCtx)
        let updatePayload = extractLastPayload(updateEvents)

        XCTAssertEqual(updatePayload?["status"], "completed")
        XCTAssertEqual(updatePayload?["action"], "update")
        XCTAssertEqual(updatePayload?["hypothesis_id"], hypothesisId)
        XCTAssertEqual(updatePayload?["hypothesis_status"], "confirmed")
    }

    func testDebugHypothesizeUpdateRejectsUnknownID() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (update, updateCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "update",
                "hypothesis_id": UUID().uuidString,
                "status": "confirmed"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(update, context: updateCtx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "failed")
        XCTAssertTrue((payload?["detail"] ?? "").contains("Unknown hypothesis_id"))
    }

    func testDebugHypothesizeUpdateAcceptsShortHypothesisPrefix() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (propose, proposeCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "propose",
                "title": "Race in cache invalidation",
                "description": "Observed stale reads in burst traffic"
            ],
            workspace: tmp
        )
        let proposeEvents = await runtime.execute(propose, context: proposeCtx)
        let proposePayload = extractLastPayload(proposeEvents)
        let fullID = proposePayload?["hypothesis_id"] ?? ""
        XCTAssertFalse(fullID.isEmpty)

        let shortID = String(fullID.prefix(8))
        let (update, updateCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "update",
                "hypothesis_id": shortID,
                "status": "confirmed",
                "evidence": "Matched by short prefix"
            ],
            workspace: tmp
        )
        let updateEvents = await runtime.execute(update, context: updateCtx)
        let updatePayload = extractLastPayload(updateEvents)

        XCTAssertEqual(updatePayload?["status"], "completed")
        XCTAssertEqual(updatePayload?["action"], "update")
        XCTAssertEqual(updatePayload?["hypothesis_id"], fullID)
        XCTAssertEqual(updatePayload?["hypothesis_status"], "confirmed")
    }
}
