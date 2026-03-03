import Foundation
import AppKit

extension CLIAccountLoginCoordinator {
    func startLoginFlow(account: CLIAccount, providerPath: String?, method: LoginMethod, apiKey: String?) {
        let executable = CLIAccountAuthDetector.resolveExecutable(provider: account.provider, providerPath: providerPath)
        guard let executable, FileManager.default.isExecutableFile(atPath: executable) else {
            statusByAccount[account.id] = "CLI not installed or invalid path"
            isRunningByAccount[account.id] = false
            return
        }

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
        env["BROWSER"] = "false"
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: account.profilePath, isDirectory: true)
        process.arguments = loginArguments(provider: account.provider, method: method, apiKey: apiKey)

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

    func pollLoginStatusFlow(account: CLIAccount, providerPath: String?) async {
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
}
