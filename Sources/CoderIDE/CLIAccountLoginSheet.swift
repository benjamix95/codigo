import SwiftUI
import AppKit
import CoderEngine

/// Universal login sheet for any CLI provider (Codex, Claude, Gemini).
/// Replaces the Codex-specific `CodexLoginView` with a provider-agnostic flow.
struct CLIAccountLoginSheet: View {
    @Environment(\.dismiss) var dismiss

    let account: CLIAccount
    let providerPath: String?
    var onDismiss: (() -> Void)?

    @StateObject private var coordinator = CLIAccountLoginCoordinator()
    @State private var apiKey = ""
    @State private var phase: LoginPhase = .options

    private enum LoginPhase {
        case options
        case polling(message: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch phase {
            case .options:
                optionsView
            case .polling(let message):
                pollingView(message: message)
            }
        }
        .frame(width: 400)
        .onReceive(coordinator.$statusByAccount) { statuses in
            guard let status = statuses[account.id] else { return }
            if status == "Connected" {
                dismiss()
                onDismiss?()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: providerIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(providerColor)
            }

            Text("Sign in to \(account.provider.displayName)")
                .font(.title3.weight(.semibold))

            Text(account.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Options

    private var optionsView: some View {
        VStack(spacing: 16) {
            // Primary: Browser OAuth
            Button(action: loginWithBrowser) {
                HStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in with Browser")
                            .font(.subheadline.weight(.medium))
                        Text(browserSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .padding(12)
                .foregroundColor(.white)
                .background(providerColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            dividerLine

            // Secondary: Device code
            Button(action: loginWithDeviceCode) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .foregroundStyle(providerColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device code")
                            .font(.subheadline.weight(.medium))
                        Text("Authenticate via terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            // Tertiary: API key
            VStack(alignment: .leading, spacing: 8) {
                Text("Or use API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                SecureField(apiKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Sign in with API Key") { loginWithAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .tint(providerColor)
                    .disabled(apiKey.isEmpty)
            }

            Button("Cancel", role: .cancel) {
                coordinator.cancelLogin(accountId: account.id)
                dismiss()
                onDismiss?()
            }
            .padding(.top, 4)
        }
        .padding(24)
    }

    // MARK: - Polling

    private func pollingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text(coordinator.statusByAccount[account.id] ?? message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Complete the login in your browser...")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Cancel") {
                coordinator.cancelLogin(accountId: account.id)
                phase = .options
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - Actions

    private func loginWithBrowser() {
        phase = .polling(message: "Opening browser...")
        coordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: .browserOAuth,
            apiKey: nil
        )
    }

    private func loginWithDeviceCode() {
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
        phase = .polling(message: "Authenticating...")

        // Store key in keychain first
        CLIAccountsStore.shared.updateSecret(accountId: account.id, secret: apiKey)

        coordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: .apiKey,
            apiKey: apiKey
        )
    }

    // MARK: - Provider Styling

    private var providerColor: Color {
        switch account.provider {
        case .codex: return .green
        case .claude: return .orange
        case .gemini: return .blue
        }
    }

    private var providerIcon: String {
        switch account.provider {
        case .codex: return "terminal"
        case .claude: return "brain.head.profile"
        case .gemini: return "sparkles"
        }
    }

    private var browserSubtitle: String {
        switch account.provider {
        case .codex: return "Sign in with your ChatGPT account"
        case .claude: return "Sign in with your Anthropic account"
        case .gemini: return "Sign in with your Google account"
        }
    }

    private var apiKeyPlaceholder: String {
        switch account.provider {
        case .codex: return "sk-..."
        case .claude: return "sk-ant-..."
        case .gemini: return "AIza..."
        }
    }

    private var dividerLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            Text("or").font(.caption).foregroundStyle(.tertiary)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
        }
    }
}
