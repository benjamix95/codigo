import CoderEngine
import XCTest
@testable import CoderIDE

extension CLIProfileProvisionerTests {
    func testCodexMCPFallbackBinaryPathIsAbsolute() {
        XCTAssertEqual(CLIProfileProvisioner.codexProfileMCPFallbackBinaryPath, "/usr/bin/coderide-mcp-server-rust")
        XCTAssertTrue(CLIProfileProvisioner.codexProfileMCPFallbackBinaryPath.hasPrefix("/"))
    }

    func testDevelopmentMCPServerBinaryPathFindsNewestRepoBuildArtifact() throws {
        let repoRoot = try makeTemporaryProfileDirectory()
        let sourceDir = repoRoot
            .appendingPathComponent("App/SoloCodeApp/Sources/Accounts/Support/Provisioning", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("CLIProfileProvisioner+Paths.swift")
        try "".write(to: sourceFile, atomically: true, encoding: .utf8)

        let preferred = repoRoot
            .appendingPathComponent(".build/rust-mcp-server/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)
        let preferredBinary = preferred.appendingPathComponent("coderide-mcp-server-rust")
        try "#!/bin/sh\nexit 0\n".write(to: preferredBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: preferredBinary.path)

        let fallback = repoRoot
            .appendingPathComponent("Native/target/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        let fallbackBinary = fallback.appendingPathComponent("coderide-mcp-server-rust")
        try "#!/bin/sh\nexit 0\n".write(to: fallbackBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: fallbackBinary.path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: fallbackBinary.path)

        XCTAssertEqual(
            CLIProfileProvisioner.newestExecutablePath(
                CLIProfileProvisioner.developmentMCPServerBinaryPaths(sourceFilePath: sourceFile.path)
            ),
            fallbackBinary.path
        )
    }

    func testMCPServerBinaryPathPrefersNativeTargetOverBuildMirror() throws {
        let repoRoot = try makeTemporaryProfileDirectory()
        let sourceDir = repoRoot
            .appendingPathComponent("App/SoloCodeApp/Sources/Accounts/Support/Provisioning", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("CLIProfileProvisioner+Paths.swift")
        try "".write(to: sourceFile, atomically: true, encoding: .utf8)

        let buildDir = repoRoot
            .appendingPathComponent(".build/rust-mcp-server/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let buildBinary = buildDir.appendingPathComponent("coderide-mcp-server-rust")
        try "#!/bin/sh\nexit 0\n".write(to: buildBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: buildBinary.path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: buildBinary.path)

        let targetDir = repoRoot
            .appendingPathComponent("Native/target/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetBinary = targetDir.appendingPathComponent("coderide-mcp-server-rust")
        try "#!/bin/sh\nexit 0\n".write(to: targetBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: targetBinary.path)

        XCTAssertEqual(
            CLIProfileProvisioner.firstExecutablePath(
                CLIProfileProvisioner.developmentMCPServerBinaryPaths(sourceFilePath: sourceFile.path)
            ),
            targetBinary.path
        )
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

    func testDefaultCodexProfilePathCopiesGlobalAuthIntoManagedDefaultProfile() throws {
        let managedRoot = try makeTemporaryProfileDirectory()
        let fakeMCP = try makeTemporaryExecutable(named: "coderide-mcp-server-rust")
        let sourceAuthDir = try makeTemporaryProfileDirectory()
        let sourceAuthURL = sourceAuthDir.appendingPathComponent("auth.json")
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token"
          }
        }
        """.write(to: sourceAuthURL, atomically: true, encoding: .utf8)

        let profilePath = withMCPServerPathOverride(fakeMCP.path) {
            CLIProfileProvisioner.defaultCodexProfilePath(baseProfilesRoot: managedRoot)
        }
        CLIProfileProvisioner.syncDefaultCodexAuthIfNeeded(
            baseProfilesRoot: managedRoot,
            sourceAuthPath: sourceAuthURL.path
        )

        let profileURL = URL(fileURLWithPath: profilePath, isDirectory: true)
        let copiedAuthURL = profileURL.appendingPathComponent("auth.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedAuthURL.path))
        let copied = try String(contentsOf: copiedAuthURL, encoding: .utf8)
        XCTAssertTrue(copied.contains("\"access_token\": \"access-token\""))
    }

    func testBaseProfilesDirUsesSoloCodeApplicationSupportNamespace() {
        let baseDir = CLIProfileProvisioner.baseProfilesDir()
        XCTAssertTrue(baseDir.path.contains("/Library/Application Support/Solo Code/CLIProfiles"))
    }
}
