import Foundation
import AppKit
import CoderEngine

@MainActor
final class CLIAccountLoginCoordinator: ObservableObject {
    enum LoginMethod: String, CaseIterable, Identifiable {
        case browserOAuth
        case deviceCode
        case apiKey

        var id: String { rawValue }
        var title: String {
            switch self {
            case .browserOAuth: return "Browser OAuth"
            case .deviceCode: return "Device code"
            case .apiKey: return "API key"
            }
        }
    }

    @Published private(set) var isRunningByAccount: [UUID: Bool] = [:]
    @Published private(set) var statusByAccount: [UUID: String] = [:]
    @Published private(set) var authURLByAccount: [UUID: URL] = [:]
    @Published private(set) var lastOutputByAccount: [UUID: String] = [:]

    private var loginProcesses: [UUID: Process] = [:]
    private var autoOpenedAuthURLAccounts: Set<UUID> = []

    func startLogin(account: CLIAccount, providerPath: String?, method: LoginMethod, apiKey: String?) {
        let executable = CLIAccountAuthDetector.resolveExecutable(provider: account.provider, providerPath: providerPath)
        guard let executable, FileManager.default.isExecutableFile(atPath: executable) else {
            statusByAccount[account.id] = "CLI not installed or invalid path"
            isRunningByAccount[account.id] = false
            return
        }

        // Claude API-key auth is environment-based; no interactive CLI login flow is required.
        if method == .apiKey, account.provider == .claude {
            statusByAccount[account.id] = "Connected"
            isRunningByAccount[account.id] = false
            return
        }

        isRunningByAccount[account.id] = true
        statusByAccount[account.id] = "Starting login..."
        authURLByAccount[account.id] = nil
        lastOutputByAccount[account.id] = nil
        autoOpenedAuthURLAccounts.remove(account.id)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        let env = CLIAccountAuthDetector.buildEnvironment(for: account)
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: account.profilePath, isDirectory: true)

        switch method {
        case .browserOAuth:
            process.arguments = loginArgs(provider: account.provider, method: .browserOAuth)
        case .deviceCode:
            process.arguments = loginArgs(provider: account.provider, method: .deviceCode)
        case .apiKey:
            guard let apiKey, !apiKey.isEmpty else {
                statusByAccount[account.id] = "API key missing"
                isRunningByAccount[account.id] = false
                return
            }
            process.arguments = loginArgs(provider: account.provider, method: .apiKey)
            process.standardInput = Pipe()
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let cleaned = Self.sanitizeOutput(text)
            let url = Self.extractFirstURL(from: cleaned)
            DispatchQueue.main.async {
                if let url {
                    self.authURLByAccount[account.id] = url
                    if method == .browserOAuth, !self.autoOpenedAuthURLAccounts.contains(account.id) {
                        NSWorkspace.shared.open(url)
                        self.autoOpenedAuthURLAccounts.insert(account.id)
                    }
                }

                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.lastOutputByAccount[account.id] = trimmed

                if method == .browserOAuth, self.authURLByAccount[account.id] != nil {
                    self.statusByAccount[account.id] = "Browser opened, complete the login..."
                } else {
                    self.statusByAccount[account.id] = trimmed
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                outPipe.fileHandleForReading.readabilityHandler = nil
                self.loginProcesses[account.id] = nil
                self.isRunningByAccount[account.id] = false
            }
        }

        do {
            try process.run()
            loginProcesses[account.id] = process
            if method == .apiKey, let apiKey, let input = process.standardInput as? Pipe {
                input.fileHandleForWriting.write((apiKey + "\n").data(using: .utf8) ?? Data())
                try? input.fileHandleForWriting.close()
            }
            Task { await pollLoginStatus(account: account, providerPath: providerPath) }
        } catch {
            statusByAccount[account.id] = "Login error: \(error.localizedDescription)"
            isRunningByAccount[account.id] = false
        }
    }

    func pollLoginStatus(account: CLIAccount, providerPath: String?) async {
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(2))
            let status = await CLIAccountAuthDetector.detectOffMainThread(
                account: account,
                providerPath: providerPath
            )
            if status.isLoggedIn {
                await MainActor.run {
                    isRunningByAccount[account.id] = false
                    statusByAccount[account.id] = "Connected"
                }
                return
            }
        }
        await MainActor.run {
            isRunningByAccount[account.id] = false
            if statusByAccount[account.id] == nil || statusByAccount[account.id] == "Starting login..." {
                statusByAccount[account.id] = "Login timeout"
            }
        }
    }

    func cancelLogin(accountId: UUID) {
        loginProcesses[accountId]?.terminate()
        loginProcesses[accountId] = nil
        isRunningByAccount[accountId] = false
        statusByAccount[accountId] = "Login cancelled"
        autoOpenedAuthURLAccounts.remove(accountId)
    }

    func disconnect(account: CLIAccount) {
        if CLIAccountsStore.shared.isManagedProfilePath(account.profilePath) {
            let url = URL(fileURLWithPath: account.profilePath)
            do {
                let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                if account.provider == .codex {
                    CLIProfileProvisioner.reseedCodexProfile(at: url)
                }
                statusByAccount[account.id] = "Disconnected"
            } catch {
                statusByAccount[account.id] = "Logout error: \(error.localizedDescription)"
            }
            return
        }

        if runProviderLogout(account: account) {
            statusByAccount[account.id] = "Disconnected"
        } else {
            statusByAccount[account.id] = "Global profile linked (logout unavailable)"
        }
    }

    private func loginArgs(provider: CLIProviderKind, method: LoginMethod) -> [String] {
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

    private func runProviderLogout(account: CLIAccount) -> Bool {
        guard let executable = CLIAccountAuthDetector.resolveExecutable(
            provider: account.provider,
            providerPath: nil
        ),
        FileManager.default.isExecutableFile(atPath: executable) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = logoutArgs(provider: account.provider)
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

    private func logoutArgs(provider: CLIProviderKind) -> [String] {
        switch provider {
        case .codex:
            return ["logout"]
        case .claude:
            return ["auth", "logout"]
        case .gemini:
            return ["auth", "logout"]
        }
    }

    nonisolated private static func extractFirstURL(from output: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+"),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else {
            return nil
        }
        return URL(string: String(output[range]))
    }

    nonisolated private static func sanitizeOutput(_ raw: String) -> String {
        let noANSI = raw.replacingOccurrences(
            of: "\\u001B\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let cleanedScalars = noANSI.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(cleanedScalars))
    }
}
