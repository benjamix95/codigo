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
    @Published private(set) var awaitingInputByAccount: [UUID: Bool] = [:]
    @Published private(set) var deviceCodeByAccount: [UUID: String] = [:]

    private var loginProcesses: [UUID: Process] = [:]
    private var loginInputPipes: [UUID: Pipe] = [:]
    private var pendingBrowserOpenByAccount: [UUID: URL?] = [:]

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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        let outPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.standardInput = inputPipe

        var env = CLIAccountAuthDetector.buildEnvironment(for: account)
        // Suppress CLI auto-opening the default browser so we can open in the user's chosen browser.
        env["BROWSER"] = "false"
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
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let cleaned = Self.sanitizeOutput(text)
            let url = Self.extractFirstURL(from: cleaned)
            let outputNeedsInput = Self.outputRequestsInteractiveCode(
                cleaned,
                provider: account.provider
            )
            let deviceCode = Self.extractDeviceCode(from: cleaned)
            DispatchQueue.main.async {
                if let url {
                    self.authURLByAccount[account.id] = url
                    // Auto-open in selected browser (fires once, then clears)
                    if let pending = self.pendingBrowserOpenByAccount.removeValue(forKey: account.id) {
                        if let browserURL = pending {
                            NSWorkspace.shared.open(
                                [url],
                                withApplicationAt: browserURL,
                                configuration: NSWorkspace.OpenConfiguration()
                            ) { _, _ in }
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if outputNeedsInput {
                    self.awaitingInputByAccount[account.id] = true
                }
                if let deviceCode {
                    self.deviceCodeByAccount[account.id] = deviceCode
                }

                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.lastOutputByAccount[account.id] = trimmed

                if self.awaitingInputByAccount[account.id] == true {
                    self.statusByAccount[account.id] = "Paste the authentication code and submit"
                } else if method == .browserOAuth, self.authURLByAccount[account.id] != nil {
                    self.statusByAccount[account.id] = "Complete the login in the browser"
                } else {
                    self.statusByAccount[account.id] = trimmed
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            DispatchQueue.main.async {
                outPipe.fileHandleForReading.readabilityHandler = nil
                self.loginProcesses[account.id] = nil
                self.loginInputPipes[account.id] = nil
                self.awaitingInputByAccount[account.id] = false
                self.isRunningByAccount[account.id] = false
                if proc.terminationReason == .exit,
                   proc.terminationStatus == 0,
                   self.statusByAccount[account.id] != "Login cancelled" {
                    self.statusByAccount[account.id] = "Connected"
                } else if self.statusByAccount[account.id] != "Login cancelled" {
                    self.statusByAccount[account.id] = "Login failed (exit code \(proc.terminationStatus))"
                }
            }
        }

        do {
            try process.run()
            loginProcesses[account.id] = process
            loginInputPipes[account.id] = inputPipe
            awaitingInputByAccount[account.id] = false
            if method == .apiKey, let apiKey {
                try inputPipe.fileHandleForWriting.write(
                    contentsOf: (apiKey + "\n").data(using: .utf8) ?? Data()
                )
                try? inputPipe.fileHandleForWriting.close()
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
                    awaitingInputByAccount[account.id] = false
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
        loginInputPipes[accountId] = nil
        isRunningByAccount[accountId] = false
        statusByAccount[accountId] = "Login cancelled"
        awaitingInputByAccount[accountId] = false
        deviceCodeByAccount[accountId] = nil
        pendingBrowserOpenByAccount[accountId] = nil
    }

    func setSelectedBrowser(_ browserAppURL: URL?, forAccount accountId: UUID) {
        pendingBrowserOpenByAccount[accountId] = .some(browserAppURL)
    }

    @discardableResult
    func submitInteractiveInput(accountId: UUID, text: String) -> Bool {
        let normalized = Self.normalizeInteractiveCode(text)
        guard !normalized.isEmpty else {
            statusByAccount[accountId] = "Authentication code is empty"
            return false
        }
        guard let inputPipe = loginInputPipes[accountId] else {
            statusByAccount[accountId] = "Login process not ready for input"
            return false
        }
        do {
            try inputPipe.fileHandleForWriting.write(
                contentsOf: (normalized + "\n").data(using: .utf8) ?? Data()
            )
            statusByAccount[accountId] = "Code submitted, waiting for confirmation..."
            awaitingInputByAccount[accountId] = false
            return true
        } catch {
            statusByAccount[accountId] = "Failed to submit code: \(error.localizedDescription)"
            return false
        }
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

    nonisolated static func extractDeviceCode(from output: String) -> String? {
        let patterns = [
            "(?:code|Code)\\s*(?:is)?\\s*[:：]\\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})",
            "(?:user[_\\s-]?code|device[_\\s-]?code)\\s*[:：]\\s*([A-Za-z0-9][A-Za-z0-9-]{4,})",
            "\\n\\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})\\s*\\n",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: output) else { continue }
            let code = String(output[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty, code.count >= 6 { return code }
        }
        return nil
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

    nonisolated static func outputRequestsInteractiveCode(_ output: String, provider: CLIProviderKind) -> Bool {
        let lower = output.lowercased()
        let commonHints = [
            "paste authentication code",
            "enter authentication code",
            "verification code",
            "one-time code",
            "paste code here",
            "enter code:",
            "enter the code",
            "paste the code",
            "authorization code",
            "enter your code",
            "input code",
            "paste code",
        ]
        if commonHints.contains(where: { lower.contains($0) }) {
            return true
        }
        switch provider {
        case .claude:
            let claudeHints = [
                "paste this into claude code",
                "paste into claude code",
                "authentication code",
                "if prompted, paste",
            ]
            return claudeHints.contains(where: { lower.contains($0) })
        case .codex:
            let codexHints = [
                "enter this code",
                "paste this code",
                "enter code at",
            ]
            return codexHints.contains(where: { lower.contains($0) })
        case .gemini:
            return false
        }
    }

    nonisolated private static func normalizeInteractiveCode(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in ["code:", "code "] {
            if lowered.hasPrefix(prefix) {
                let rest = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty {
                    trimmed = rest
                    break
                }
            }
        }
        return trimmed
    }
}
