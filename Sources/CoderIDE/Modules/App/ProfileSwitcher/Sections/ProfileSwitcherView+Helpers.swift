import SwiftUI
import CoderEngine

extension ProfileSwitcherView {
    func providerIcon(_ provider: CLIProviderKind) -> String {
        switch provider {
        case .codex: return "terminal"
        case .claude: return "brain.head.profile"
        case .gemini: return "sparkles"
        }
    }

    func resolveProviderPath(_ provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex:
            let custom = UserDefaults.standard.string(forKey: "codex_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .codex, providerPath: custom)
        case .claude:
            let custom = UserDefaults.standard.string(forKey: "claude_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .claude, providerPath: custom)
        case .gemini:
            let custom = UserDefaults.standard.string(forKey: "gemini_cli_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .gemini, providerPath: custom)
        }
    }

    var primaryTitle: String {
        guard let account = primaryActiveAccount else { return "No profile" }
        if let displayName = CLIAccountAuthDetector.identity(account: account)?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let email = CLIAccountAuthDetector.identity(account: account)?.email, !email.isEmpty {
            return email
        }
        return account.label
    }

    var primarySubtitle: String {
        guard let account = primaryActiveAccount else { return "Click to configure" }
        return account.provider.displayName
    }
}

extension Notification.Name {
    static let openSettingsToAccounts = Notification.Name("openSettingsToAccounts")
}
