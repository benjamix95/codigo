import Foundation

extension CLIAccountLoginCoordinator {
    func loginArguments(provider: CLIProviderKind, method: CLIAccountLoginCoordinator.LoginMethod, apiKey: String?) -> [String] {
        switch provider {
        case .codex:
            switch method {
            case .browserOAuth: return ["login"]
            case .deviceCode: return ["login", "--device-auth"]
            case .apiKey: return ["login", "--with-api-key"]
            }
        case .claude:
            switch method {
            case .browserOAuth: return ["auth", "login"]
            case .deviceCode: return ["auth", "login"]
            case .apiKey: return ["auth", "status"]
            }
        case .gemini:
            switch method {
            case .browserOAuth: return ["auth", "login"]
            case .deviceCode: return ["auth", "login", "--device-code"]
            case .apiKey: return ["auth", "login", "--api-key"]
            }
        }
    }

    func runProviderLogout(account: CLIAccount) -> Bool {
        guard let executable = CLIAccountAuthDetector.resolveExecutable(
            provider: account.provider,
            providerPath: nil
        ),
        FileManager.default.isExecutableFile(atPath: executable) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = logoutArguments(provider: account.provider)
        process.environment = CLIAccountAuthDetector.buildEnvironment(for: account)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func logoutArguments(provider: CLIProviderKind) -> [String] {
        switch provider {
        case .codex:
            return ["logout"]
        case .claude:
            return ["auth", "logout"]
        case .gemini:
            return ["auth", "logout"]
        }
    }
}
