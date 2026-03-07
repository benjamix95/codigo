import Foundation

extension CLIAccountAuthDetectorTests {
    func makeTemporaryProfileDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cli-auth-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    func makeTemporaryExecutable(named name: String, exitCode: Int = 0) throws -> URL {
        let directory = try makeTemporaryProfileDirectory()
        let executable = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit \(exitCode)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: executable.path)
        return executable
    }

    func writeCodexAuthJSON(to profile: URL, email: String, accountId: String) throws {
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

    func writeClaudeCredentialsJSON(to profile: URL) throws {
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

    func writeModernClaudeSessionJSON(to profile: URL) throws {
        let json: [String: Any] = [
            "userID": "user-modern-123",
            "hasCompletedOnboarding": true,
            "projects": [
                "/tmp/workspace": [
                    "lastTotalInputTokens": 1
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: profile.appendingPathComponent(".claude.json"))
    }

    func makeJWT(payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(base64url(headerData)).\(base64url(payloadData))."
    }

    func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
