import Foundation

extension CLIAccountLoginCoordinator {
    func cancelLoginFlow(accountId: UUID) {
        loginProcesses[accountId]?.terminate()
        loginProcesses[accountId] = nil
        loginInputPipes[accountId] = nil
        isRunningByAccount[accountId] = false
        statusByAccount[accountId] = "Login cancelled"
        awaitingInputByAccount[accountId] = false
        deviceCodeByAccount[accountId] = nil
        pendingBrowserOpenByAccount[accountId] = nil
    }

    func submitInteractiveInputFlow(accountId: UUID, text: String) -> Bool {
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

    func disconnectFlow(account: CLIAccount) {
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
}
