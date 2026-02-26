import XCTest
@testable import CoderIDE

final class CLIAccountAuthDetectorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

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

    private func makeTemporaryProfileDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cli-auth-tests-\(UUID().uuidString)", isDirectory: true)
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

    private func writeCodexAuthJSON(to profile: URL, email: String, accountId: String) throws {
        let idToken = makeJWT(payload: [
            "email": email
        ])

        let json: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "id_token": idToken,
                "access_token": "dummy",
                "refresh_token": "dummy",
                "account_id": accountId
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: profile.appendingPathComponent("auth.json"))
    }

    private func writeClaudeCredentialsJSON(to profile: URL) throws {
        let claudeDir = profile.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "token-value",
                "refreshToken": "refresh-value",
                "expiresAt": "2099-01-01T00:00:00.000Z"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: claudeDir.appendingPathComponent(".credentials.json"))
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64url(headerData)).\(base64url(payloadData))."
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
