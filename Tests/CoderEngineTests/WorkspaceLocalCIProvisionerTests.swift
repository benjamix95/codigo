import XCTest
@testable import CoderEngine

final class WorkspaceLocalCIProvisionerTests: XCTestCase {
    func testProvisionerWritesWorkflowAndScriptForNode() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "{}".write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        WorkspaceLocalCIProvisioner.provision(roots: [tempDir])

        let wf = tempDir.appendingPathComponent(WorkspaceLocalCIProvisioner.workflowRelativePath)
        let sh = tempDir.appendingPathComponent(WorkspaceLocalCIProvisioner.shellScriptRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wf.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sh.path))

        let yaml = try String(contentsOf: wf, encoding: .utf8)
        XCTAssertTrue(yaml.contains("@solocode-managed"))
        XCTAssertTrue(yaml.contains("job-1-nodeNpm") || yaml.contains("node"))

        let script = try String(contentsOf: sh, encoding: .utf8)
        XCTAssertTrue(script.contains("@solocode-managed"))
        XCTAssertTrue(script.contains("npm"))
    }

    func testProvisionerSkipsWhenUserRemovedManagedMarker() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "{}".write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let wf = tempDir.appendingPathComponent(WorkspaceLocalCIProvisioner.workflowRelativePath)
        try FileManager.default.createDirectory(at: wf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# custom\nname: X\n".write(to: wf, atomically: true, encoding: .utf8)

        WorkspaceLocalCIProvisioner.provision(roots: [tempDir])

        let after = try String(contentsOf: wf, encoding: .utf8)
        XCTAssertTrue(after.hasPrefix("# custom"))
    }
}
