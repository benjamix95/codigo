import XCTest
@testable import CoderIDE
import Darwin

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
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")

        let env = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.environmentOverrides(
                provider: .codex,
                profilePath: profile.path,
                secret: nil
            )
        }

        XCTAssertEqual(env["CODEX_HOME"], profile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("instructions.md").path))

        let config = try String(contentsOf: profile.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config, expectedCodexConfig(using: fakeMCP.path))

        let agents = try String(contentsOf: profile.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertEqual(agents, CLIProfileProvisioner.effectiveAgentsContent())
    }

    func testReseedCodexProfileOverwritesStaleFiles() throws {
        let profile = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
        let configURL = profile.appendingPathComponent("config.toml")
        let agentsURL = profile.appendingPathComponent("AGENTS.md")
        let instructionsURL = profile.appendingPathComponent("instructions.md")

        try "legacy config\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "legacy agents\n".write(to: agentsURL, atomically: true, encoding: .utf8)
        try "legacy instructions\n".write(to: instructionsURL, atomically: true, encoding: .utf8)

        withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.reseedCodexProfile(at: profile)
        }

        let config = try String(contentsOf: configURL, encoding: .utf8)
        let agents = try String(contentsOf: agentsURL, encoding: .utf8)
        XCTAssertEqual(config, expectedCodexConfig(using: fakeMCP.path))
        XCTAssertEqual(agents, CLIProfileProvisioner.effectiveAgentsContent())
    }

    func testCodexEnvironmentOverridesRepairsMissingMCPBlockInExistingConfig() throws {
        let profile = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
        let configURL = profile.appendingPathComponent("config.toml")

        try """
        # Existing profile
        sandbox_mode = "danger-full-access"

        [sandbox_workspace_write]
        network_access = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.environmentOverrides(
                provider: .codex,
                profilePath: profile.path,
                secret: nil
            )
        }

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("[mcp_servers.coderide]"))
        XCTAssertTrue(config.contains("command = \"\(fakeMCP.path)\""))
        XCTAssertTrue(config.contains("fast_mode = true"))
    }

    func testCodexEnvironmentOverridesUpdatesExistingCoderIDEMCPPath() throws {
        let profile = try makeTemporaryProfileDirectory()
        let oldMCP = try makeTemporaryExecutable(named: "old-coderide-mcp-server-rust")
        let newMCP = try makeTemporaryExecutable(named: "new-coderide-mcp-server-rust")
        let configURL = profile.appendingPathComponent("config.toml")

        try """
        # Existing profile
        sandbox_mode = "danger-full-access"

        [sandbox_workspace_write]
        network_access = true

        [mcp_servers.coderide]
        command = "\(oldMCP.path)"
        args = [ "--workspace", "." ]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = withMCPServerPathOverride(newMCP.path) {
            CLIProfileProvisioner.environmentOverrides(
                provider: .codex,
                profilePath: profile.path,
                secret: nil
            )
        }

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("[mcp_servers.coderide]"))
        XCTAssertFalse(config.contains("command = \"\(oldMCP.path)\""))
        XCTAssertTrue(config.contains("command = \"\(newMCP.path)\""))
        XCTAssertTrue(config.contains("fast_mode = true"))
    }

    func testCodexEnvironmentOverridesRemovesUnsupportedCoderIDEMCPEnabledFlag() throws {
        let profile = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
        let configURL = profile.appendingPathComponent("config.toml")

        try """
        # Existing profile
        sandbox_mode = "danger-full-access"
        fast_mode = true

        [mcp_servers.coderide]
        command = "\(fakeMCP.path)"
        args = [ "--workspace", "." ]
        enabled = false
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.environmentOverrides(
                provider: .codex,
                profilePath: profile.path,
                secret: nil
            )
        }

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(config.contains("enabled = false"))
        XCTAssertFalse(config.contains("enabled = true"))
    }

    func testCodexEnvironmentOverridesRepairsLegacyManagedConfigToCurrentTemplate() throws {
        let profile = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
        let configURL = profile.appendingPathComponent("config.toml")

        try """
        # CoderIDE Codex Profile — auto-generated
        sandbox_mode = "danger-full-access"

        [sandbox_workspace_write]
        network_access = true

        [mcp_servers.coderide]
        command = "\(fakeMCP.path)"
        args = [ "--workspace", "." ]

        [features]
        js_repl = true
        multi_agent = true
        apps = true
        prevent_idle_sleep = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.environmentOverrides(
                provider: .codex,
                profilePath: profile.path,
                secret: nil
            )
        }

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(config, expectedCodexConfig(using: fakeMCP.path))
    }


    func testCodexMCPFallbackBinaryPathIsAbsolute() {
        XCTAssertEqual(CLIProfileProvisioner.codexProfileMCPFallbackBinaryPath, "/usr/bin/coderide-mcp-server-rust")
        XCTAssertTrue(CLIProfileProvisioner.codexProfileMCPFallbackBinaryPath.hasPrefix("/"))
    }

    func testDefaultCodexProfilePathSeedsManagedProfileUnderProvidedRoot() throws {
        let managedRoot = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")

        let profilePath = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.defaultCodexProfilePath(baseProfilesRoot: managedRoot)
        }

        let profileURL = URL(fileURLWithPath: profilePath, isDirectory: true)
        XCTAssertEqual(profileURL.lastPathComponent, "_default")
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("instructions.md").path))

        let config = try String(contentsOf: profileURL.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config, expectedCodexConfig(using: fakeMCP.path))
    }

    func testClaudeEnvironmentOverridesIsolateHomePerProfile() throws {
        let profile = try makeTemporaryProfileDirectory()

        let env = CLIProfileProvisioner.environmentOverrides(
            provider: .claude,
            profilePath: profile.path,
            secret: "sk-ant-test"
        )

        let expectedClaudeHome = profile.appendingPathComponent(".claude", isDirectory: true).path
        XCTAssertEqual(env["HOME"], profile.path)
        XCTAssertEqual(env["CLAUDE_HOME"], expectedClaudeHome)
        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "sk-ant-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedClaudeHome))
    }

    @MainActor
    func testDisconnectReseedsCodexProfile() throws {
        let managedRoot = CLIProfileProvisioner.baseProfilesDir()
            .appendingPathComponent("codex", isDirectory: true)
        let profile = managedRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        temporaryDirectories.append(profile)
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
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

        withMCPServerPathOverride(fakeMCP.path) {
            coordinator.disconnect(account: account)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("config.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.appendingPathComponent("instructions.md").path))

        let config = try String(contentsOf: profile.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config, expectedCodexConfig(using: fakeMCP.path))
    }

    private func makeTemporaryProfileDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cli-profile-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeTemporaryExecutable(named name: String) throws -> URL {
        let directory = try makeTemporaryProfileDirectory()
        let executable = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: executable.path)
        return executable
    }

    private func withMCPServerPathOverride<T>(_ path: String, operation: () throws -> T) rethrows -> T {
        let key = "CODERIDE_MCP_SERVER_PATH"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try operation()
    }

    private func expectedCodexConfig(using binaryPath: String) -> String {
        CLIProfileProvisioner.codexProfileConfigContent(binaryPath: binaryPath)
    }
}
