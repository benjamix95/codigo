import Foundation
import XCTest
@testable import CoderEngine

final class InstructionPolicyBundleTests: XCTestCase {
    func testHashForPolicyIsDeterministic() {
        let text = "line1\nline2\nline3"
        let h1 = InstructionPolicyBundle.hashForPolicy(text)
        let h2 = InstructionPolicyBundle.hashForPolicy(text)

        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, 64)
    }

    func testLoadBuildsAckMarkerWhenPolicyExists() throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instruction-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let agents = tmpRoot.appendingPathComponent("AGENTS.md")
        try "Parla italiano".write(to: agents, atomically: true, encoding: .utf8)

        let bundle = InstructionPolicyBundle.load(workspacePaths: [tmpRoot.path])
        XCTAssertTrue(bundle.hasPolicy)
        XCTAssertFalse(bundle.policyHash.isEmpty)
        XCTAssertEqual(bundle.requiredAckMarker, "[CODERIDE:policy_ack|hash=\(bundle.policyHash)]")
        XCTAssertTrue(bundle.policyText.contains(bundle.requiredAckMarker))
    }
}
