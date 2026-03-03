import SwiftUI
import AppKit

extension CLIAccountLoginSheet {
    // MARK: - Actions
    private func loginWithBrowser(browserAppURL: URL? = nil) {
        coordinator.setSelectedBrowser(browserAppURL, forAccount: account.id)
        authCodeInput = ""
        authCodeHint = ""
        deviceCodeCopied = false
        phase = .polling(message: "Opening browser...")
        coordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: .browserOAuth,
            apiKey: nil
        )
    }

    private func loginWithDeviceCode() {
        authCodeInput = ""
        authCodeHint = ""
        phase = .polling(message: "Generating device code...")
        coordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: .deviceCode,
            apiKey: nil
        )
    }

    private func loginWithAPIKey() {
        guard !apiKey.isEmpty else { return }
        authCodeInput = ""
        authCodeHint = ""
        phase = .polling(message: "Authenticating...")

        CLIAccountsStore.shared.updateSecret(accountId: account.id, secret: apiKey)
        coordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: .apiKey,
            apiKey: apiKey
        )
    }
}
