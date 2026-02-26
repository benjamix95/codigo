import XCTest
@testable import CoderIDE

final class CLIProfileProvisionerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testCodexEnvironmentOverridesSeedsMissingProfileFiles() throws {
        let profile = try makeTemporaryProfileDirectory()

        let env = CLIProfileProvisioner.environmentOverrides(
            provider: .codex,
            profilePath: profile.path,
            secret: nil
        )

        XCTAssertEqual(env["CODEX_HOME"], profile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("instructions.md").path))

        let config = try String(contentsOf: profile.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("sandbox_mode = \"danger-full-access\""))
        XCTAssertTrue(config.contains("[sandbox_workspace_write]"))

        let instructions = try String(contentsOf: profile.appendingPathComponent("instructions.md"), encoding: .utf8)
        XCTAssertTrue(instructions.contains("# CoderIDE Integration"))
    }

    func testReseedCodexProfileOverwritesStaleFiles() throws {
        let profile = try makeTemporaryProfileDirectory()
        let configURL = profile.appendingPathComponent("config.toml")
        let instructionsURL = profile.appendingPathComponent("instructions.md")

        try "legacy config\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "legacy instructions\n".write(to: instructionsURL, atomically: true, encoding: .utf8)

        CLIProfileProvisioner.reseedCodexProfile(at: profile)

        let config = try String(contentsOf: configURL, encoding: .utf8)
        let instructions = try String(contentsOf: instructionsURL, encoding: .utf8)
        XCTAssertNotEqual(config, "legacy config\n")
        XCTAssertNotEqual(instructions, "legacy instructions\n")
        XCTAssertTrue(config.contains("sandbox_mode = \"danger-full-access\""))
        XCTAssertTrue(instructions.contains("# CoderIDE Integration"))
    }

    @MainActor
    func testDisconnectReseedsCodexProfile() throws {
        let profile = try makeTemporaryProfileDirectory()
        let staleFile = profile.appendingPathComponent("stale.txt")
        try "stale".write(to: staleFile, atomically: true, encoding: .utf8)

        let account = CLIAccount(
            id: UUID(),
            provider: .codex,
            label: "Codex Test",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )
        let coordinator = CLIAccountLoginCoordinator()

        coordinator.disconnect(account: account)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("instructions.md").path))
    }

    private func makeTemporaryProfileDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cli-profile-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
