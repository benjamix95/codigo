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

    private var loginProcesses: [UUID: Process] = [:]

    func startLogin(account: CLIAccount, providerPath: String?, method: LoginMethod, apiKey: String?) {
        let executable = CLIAccountAuthDetector.resolveExecutable(provider: account.provider, providerPath: providerPath)
        guard let executable, FileManager.default.isExecutableFile(atPath: executable) else {
            statusByAccount[account.id] = "CLI non installato o path non valido"
            isRunningByAccount[account.id] = false
            return
        }

        isRunningByAccount[account.id] = true
        statusByAccount[account.id] = "Avvio login..."

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
                statusByAccount[account.id] = "API key mancante"
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
            if let regex = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text),
               let url = URL(string: String(text[range])) {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                    self.statusByAccount[account.id] = "Browser aperto, completa il login..."
                }
            }
            DispatchQueue.main.async {
                if self.statusByAccount[account.id]?.contains("Browser aperto") != true {
                    self.statusByAccount[account.id] = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            statusByAccount[account.id] = "Errore login: \(error.localizedDescription)"
            isRunningByAccount[account.id] = false
        }
    }

    func pollLoginStatus(account: CLIAccount, providerPath: String?) async {
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(2))
            let status = CLIAccountAuthDetector.detect(account: account, providerPath: providerPath)
            if status.isLoggedIn {
                await MainActor.run {
                    isRunningByAccount[account.id] = false
                    statusByAccount[account.id] = "Connesso"
                }
                return
            }
        }
        await MainActor.run {
            isRunningByAccount[account.id] = false
            if statusByAccount[account.id] == nil || statusByAccount[account.id] == "Avvio login..." {
                statusByAccount[account.id] = "Timeout login"
            }
        }
    }

    func cancelLogin(accountId: UUID) {
        loginProcesses[accountId]?.terminate()
        loginProcesses[accountId] = nil
        isRunningByAccount[accountId] = false
        statusByAccount[accountId] = "Login annullato"
    }

    func disconnect(account: CLIAccount) {
        let url = URL(fileURLWithPath: account.profilePath)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            statusByAccount[account.id] = "Disconnesso"
        } catch {
            statusByAccount[account.id] = "Errore disconnessione: \(error.localizedDescription)"
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
            case .browserOAuth: return ["login"]
            case .deviceCode: return ["login", "--device-code"]
            case .apiKey: return ["login", "--api-key"]
            }
        case .gemini:
            switch method {
            case .browserOAuth: return ["auth", "login"]
            case .deviceCode: return ["auth", "login", "--device-code"]
            case .apiKey: return ["auth", "login", "--api-key"]
            }
        }
    }
}
