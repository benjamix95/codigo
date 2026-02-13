import XCTest
@testable import CoderEngine

final class TestProjectDetectorTests: XCTestCase {
    func testDetectSwiftPackage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageSwift = tempDir.appendingPathComponent("Package.swift")
        try "// test".write(to: packageSwift, atomically: true, encoding: .utf8)

        let type = TestProjectDetector.detect(workspacePath: tempDir)
        XCTAssertEqual(type, .swift)
    }

    func testDetectNodeProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageJson = tempDir.appendingPathComponent("package.json")
        try "{}".write(to: packageJson, atomically: true, encoding: .utf8)

        let type = TestProjectDetector.detect(workspacePath: tempDir)
        XCTAssertEqual(type, .node)
    }

    func testDetectPythonProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pyproject = tempDir.appendingPathComponent("pyproject.toml")
        try "[project]".write(to: pyproject, atomically: true, encoding: .utf8)

        let type = TestProjectDetector.detect(workspacePath: tempDir)
        XCTAssertEqual(type, .python)
    }

    func testDetectUnknown() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let type = TestProjectDetector.detect(workspacePath: tempDir)
        XCTAssertEqual(type, .unknown)
    }

    func testTestCommandSwift() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try "".write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let cmd = TestProjectDetector.testCommand(workspacePath: tempDir)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd!.arguments.contains("test"))
    }

    func testTestCommandUnknownReturnsNil() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cmd = TestProjectDetector.testCommand(workspacePath: tempDir)
        XCTAssertNil(cmd)
    }
}
