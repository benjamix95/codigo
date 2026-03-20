import XCTest
@testable import CoderIDE

final class CLIAccountAuthDetectorTests: XCTestCase {
    var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDetectOnMainThreadUsesProfileAuthArtifactsForCodexOAuth() throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "codex")
        try writeCodexAuthJSON(
            to: profile,
            email: "tester@example.com",
            accountId: "acct-123"
        )

        let account = CLIAccount(
            id: UUID(),
            provider: .codex,
            label: "Account 1",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = CLIAccountAuthDetector.detect(
            account: account,
            providerPath: executable.path
        )
        XCTAssertEqual(status, .loggedIn(method: .oauth))

        let identity = CLIAccountAuthDetector.identity(account: account)
        XCTAssertEqual(identity?.email, "tester@example.com")
        XCTAssertEqual(identity?.accountId, "acct-123")
    }

    func testDetectOffMainThreadReturnsLoggedInForCodexProfile() async throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "codex")
        try writeCodexAuthJSON(
            to: profile,
            email: "runner@example.com",
            accountId: "acct-456"
        )

        let account = CLIAccount(
            id: UUID(),
            provider: .codex,
            label: "Account 2",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = await CLIAccountAuthDetector.detectOffMainThread(
            account: account,
            providerPath: executable.path
        )
        XCTAssertTrue(status.isLoggedIn)
    }

    func testDetectOnMainThreadUsesClaudeHiddenCredentialsFile() throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "claude")
        try writeClaudeCredentialsJSON(to: profile)

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude Account",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = CLIAccountAuthDetector.detect(
            account: account,
            providerPath: executable.path
        )
        XCTAssertEqual(status, .loggedIn(method: .oauth))
    }

    func testDetectOnMainThreadUsesModernClaudeSessionFileWithUserID() throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "claude")
        try writeModernClaudeSessionJSON(to: profile)

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude Modern",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = CLIAccountAuthDetector.detect(
            account: account,
            providerPath: executable.path
        )
        XCTAssertEqual(status, .loggedIn(method: .oauth))
    }

    func testDetectOnMainThreadUsesFallbackForClaudeWhenStatusCommandWouldBlockUI() throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "claude", exitCode: 1)
        try writeModernClaudeSessionJSON(to: profile)

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude stale",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = CLIAccountAuthDetector.detect(
            account: account,
            providerPath: executable.path
        )
        XCTAssertEqual(status, .loggedIn(method: .oauth))
    }

    func testDetectOffMainThreadClaudeStatusCommandWinsOverStaleProfileMarkers() async throws {
        let profile = try makeTemporaryProfileDirectory()
        let executable = try makeTemporaryExecutable(named: "claude", exitCode: 1)
        try writeModernClaudeSessionJSON(to: profile)

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude stale",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let status = await CLIAccountAuthDetector.detectOffMainThread(
            account: account,
            providerPath: executable.path
        )
        XCTAssertEqual(status, .notLoggedIn)
    }

    func testClaudeIdentityReadsAuthStatusSnapshotEmail() throws {
        let profile = try makeTemporaryProfileDirectory()
        let authStatusDir = profile.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: authStatusDir, withIntermediateDirectories: true)

        let json: [String: Any] = [
            "loggedIn": true,
            "email": "claude@example.com",
            "orgId": "org-123"
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: authStatusDir.appendingPathComponent("auth-status.json"))

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude Account",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let identity = CLIAccountAuthDetector.identity(account: account)
        XCTAssertEqual(identity?.email, "claude@example.com")
        XCTAssertEqual(identity?.accountId, "org-123")
        XCTAssertEqual(identity?.authMethod, .oauth)
    }

    func testClaudeIdentityReadsDisplayNameAndEmailFromClaudeJSON() throws {
        let profile = try makeTemporaryProfileDirectory()
        let json: [String: Any] = [
            "oauthAccount": [
                "emailAddress": "claude-profile@example.com",
                "displayName": "Claude Profile",
                "organizationUuid": "org-display-123"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: profile.appendingPathComponent(".claude.json"))

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude Account",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let identity = CLIAccountAuthDetector.identity(account: account)
        XCTAssertEqual(identity?.email, "claude-profile@example.com")
        XCTAssertEqual(identity?.displayName, "Claude Profile")
        XCTAssertEqual(identity?.accountId, "org-display-123")
        XCTAssertEqual(identity?.authMethod, .oauth)
    }

    func testClaudeIdentityReadsUserIDFromModernClaudeJSON() throws {
        let profile = try makeTemporaryProfileDirectory()
        try writeModernClaudeSessionJSON(to: profile)

        let account = CLIAccount(
            id: UUID(),
            provider: .claude,
            label: "Claude Modern",
            isEnabled: true,
            priority: 0,
            profilePath: profile.path,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )

        let identity = CLIAccountAuthDetector.identity(account: account)
        XCTAssertEqual(identity?.accountId, "user-modern-123")
        XCTAssertEqual(identity?.authMethod, .oauth)
    }

    func testHasEnvironmentCredentialDetectsProviderSpecificSecrets() throws {
        let secrets = CLIAccountSecretsStore()
        let cases: [(CLIProviderKind, String)] = [(.codex, "openai-key"), (.claude, "anthropic-key"), (.gemini, "google-key")]

        for (provider, secret) in cases {
            let profile = try makeTemporaryProfileDirectory()
            let account = CLIAccount(
                id: UUID(),
                provider: provider,
                label: provider.rawValue,
                isEnabled: true,
                priority: 0,
                profilePath: profile.path,
                quota: .empty,
                health: .healthy,
                createdAt: .now,
                updatedAt: .now
            )
            secrets.setSecret(secret, for: account.id)
            defer { secrets.deleteSecret(for: account.id) }

            XCTAssertTrue(
                CLIAccountAuthDetector.hasEnvironmentCredential(account: account),
                "expected environment credential for \(provider.rawValue)"
            )
        }
    }
}
