import XCTest
import CoderEngine
@testable import CoderIDE

final class CLIMultiAccountProviderAdapterTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var suiteNames: [String] = []

    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(
                forName: suiteName
            )
        }
        suiteNames.removeAll()

        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testHasAuthenticatedAvailableAccountReturnsFalseForLoggedOutCodexAccount() throws {
        let defaults = makeSuiteDefaults()
        let profile = try makeTemporaryDirectory(prefix: "cli-multi-profile")
        let executable = try makeTemporaryExecutable(named: "codex")
        defaults.set(executable.path, forKey: "codex_path")

        try seedAccounts(
            [
                makeCodexAccount(profilePath: profile.path)
            ],
            defaults: defaults
        )

        XCTAssertFalse(
            CLIMultiAccountProviderAdapter.hasAuthenticatedAvailableAccount(
                providerKind: .codex,
                userDefaults: defaults
            )
        )
    }

    func testHasAuthenticatedAvailableAccountReturnsTrueForLoggedInCodexAccount() throws {
        let defaults = makeSuiteDefaults()
        let profile = try makeTemporaryDirectory(prefix: "cli-multi-profile")
        let executable = try makeTemporaryExecutable(named: "codex")
        defaults.set(executable.path, forKey: "codex_path")
        try writeCodexAuthJSON(
            to: profile,
            email: "multi@example.com",
            accountId: "acct-multi-123"
        )

        try seedAccounts(
            [
                makeCodexAccount(profilePath: profile.path)
            ],
            defaults: defaults
        )

        XCTAssertTrue(
            CLIMultiAccountProviderAdapter.hasAuthenticatedAvailableAccount(
                providerKind: .codex,
                userDefaults: defaults
            )
        )
    }

    func testHasAuthenticatedAvailableAccountIgnoresExhaustedAccount() throws {
        let defaults = makeSuiteDefaults()
        let profile = try makeTemporaryDirectory(prefix: "cli-multi-profile")
        let executable = try makeTemporaryExecutable(named: "codex")
        defaults.set(executable.path, forKey: "codex_path")
        try writeCodexAuthJSON(
            to: profile,
            email: "multi@example.com",
            accountId: "acct-multi-456"
        )

        let exhausted = CLIAccountHealth(
            cooldownUntil: nil,
            lastErrorCode: "local_limit_reached",
            consecutiveFailures: 3,
            isExhaustedLocally: true
        )

        try seedAccounts(
            [
                makeCodexAccount(
                    profilePath: profile.path,
                    health: exhausted
                )
            ],
            defaults: defaults
        )

        XCTAssertFalse(
            CLIMultiAccountProviderAdapter.hasAuthenticatedAvailableAccount(
                providerKind: .codex,
                userDefaults: defaults
            )
        )
    }

    private func makeSuiteDefaults() -> UserDefaults {
        let suiteName = "CLIMultiAccountProviderAdapterTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedAccounts(
        _ accounts: [CLIAccount],
        defaults: UserDefaults
    ) throws {
        let data = try JSONEncoder().encode(accounts)
        defaults.set(data, forKey: "CoderIDE.cliAccounts")
    }

    private func makeCodexAccount(
        profilePath: String,
        health: CLIAccountHealth = .healthy
    ) -> CLIAccount {
        CLIAccount(
            id: UUID(),
            provider: .codex,
            label: "Codex Account",
            isEnabled: true,
            priority: 0,
            profilePath: profilePath,
            quota: .empty,
            health: health,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeTemporaryExecutable(named name: String) throws -> URL {
        let directory = try makeTemporaryDirectory(prefix: "cli-multi-bin")
        let executable = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: executable.path
        )
        return executable
    }

    private func writeCodexAuthJSON(
        to profile: URL,
        email: String,
        accountId: String
    ) throws {
        let idToken = makeJWT(payload: ["email": email])
        let json: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "id_token": idToken,
                "access_token": "dummy",
                "refresh_token": "dummy",
                "account_id": accountId,
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted]
        )
        try data.write(to: profile.appendingPathComponent("auth.json"))
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(
            withJSONObject: ["alg": "none", "typ": "JWT"]
        )
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
