import SwiftUI
import AppKit
import Foundation

extension CLIAccountLoginSheet {
    struct BrowserApp: Identifiable {
        let id: String
        let name: String
        let url: URL
        let isDefault: Bool
    }

    var providerColor: Color {
        switch account.provider {
        case .codex: return .green
        case .claude: return .orange
        case .gemini: return .blue
        }
    }

    var providerIcon: String {
        switch account.provider {
        case .codex: return "terminal"
        case .claude: return "brain.head.profile"
        case .gemini: return "sparkles"
        }
    }

    var browserSubtitle: String {
        switch account.provider {
        case .codex: return "Sign in with your ChatGPT account"
        case .claude: return "Sign in with your Anthropic account"
        case .gemini: return "Sign in with your Google account"
        }
    }

    var apiKeyPlaceholder: String {
        switch account.provider {
        case .codex: return "sk-..."
        case .claude: return "sk-ant-..."
        case .gemini: return "AIza..."
        }
    }

    var supportsDeviceCode: Bool {
        account.provider != .claude
    }

    var isLoginSuccess: Bool {
        guard let status = coordinator.statusByAccount[account.id] else { return false }
        return statusIsSuccess(status)
    }

    var isLoginRunning: Bool {
        coordinator.isRunningByAccount[account.id] == true
    }

    var shouldShowAuthCodeInput: Bool {
        if coordinator.awaitingInputByAccount[account.id] == true {
            return true
        }
        if case .polling = phase {
            return true
        }
        return false
    }

    var dividerLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            Text("or").font(.caption).foregroundStyle(.tertiary)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
        }
    }

    func statusIsSuccess(_ status: String) -> Bool {
        let lower = status.lowercased()
        return status == "Connected"
            || lower.contains("logged in")
            || lower.contains("login successful")
            || lower.contains("authenticated")
    }

    func copyToClipboard(value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func open(_ url: URL, with browserURL: URL) {
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }
}
