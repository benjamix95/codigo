import SwiftUI
import AppKit
import CoderEngine

struct CodexLoginView: View {
    @Environment(\.dismiss) var dismiss
    let codexPath: String
    let onDismiss: () -> Void

    @State private var apiKey = ""
    @State private var isPolling = false
    @State private var loginMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            loginHeader
            Divider()
            if isPolling {
                pollingView
            } else {
                loginOptionsView
            }
        }
        .frame(width: 400)
    }

    private var loginHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("Sign in to Codex")
                .font(.title3)

            Text("Authenticate to use Codex CLI")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var pollingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text(loginMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Please wait...")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }

    private var loginOptionsView: some View {
        VStack(spacing: 16) {
            Button(action: loginWithBrowser) {
                HStack {
                    Image(systemName: "safari")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in with ChatGPT")
                            .font(.subheadline.weight(.medium))
                        Text("Open the browser to authenticate")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(12)
                .foregroundColor(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            HStack {
                Divider().frame(height: 1)
                Text("or").font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 1)
            }

            Button(action: loginWithDeviceCode) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device code")
                            .font(.subheadline.weight(.medium))
                        Text("Show code in terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("Or use API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                SecureField("openai_api_key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Sign in with API Key") { loginWithAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)
            }

            Button("Cancel", role: .cancel) {
                dismiss()
                onDismiss()
            }
            .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - Login Actions

    private func loginWithBrowser() {
        isPolling = true
        loginMessage = "Opening the browser..."
        performLogin { await CodexLoginService.runBrowserLogin(codexPath: codexPath, args: []) }
    }

    private func loginWithDeviceCode() {
        isPolling = true
        loginMessage = "Showing the code in terminal..."
        performLogin { await CodexLoginService.runBrowserLogin(codexPath: codexPath, args: ["--device-auth"]) }
    }

    private func loginWithAPIKey() {
        guard !apiKey.isEmpty else { return }
        isPolling = true
        loginMessage = "Authenticating..."
        performLogin { await CodexLoginService.loginWithAPIKey(codexPath: codexPath, apiKey: apiKey) }
    }

    /// Shared handler: runs an async login operation and updates UI based on result.
    private func performLogin(_ operation: @escaping () async -> CodexLoginService.LoginResult) {
        Task {
            let result = await operation()
            handleResult(result)
        }
    }

    private func handleResult(_ result: CodexLoginService.LoginResult) {
        switch result {
        case .success:
            isPolling = false
            dismiss()
            onDismiss()
        case .failure(let message):
            isPolling = false
            loginMessage = message
        case .timeout:
            isPolling = false
            loginMessage = "Timeout. Try again."
        }
    }
}
