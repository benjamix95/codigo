import SwiftUI
import AppKit
import CoderEngine

/// Universal login sheet for any CLI provider (Codex, Claude, Gemini).
/// Replaces the Codex-specific `CodexLoginView` with a provider-agnostic flow.
struct CLIAccountLoginSheet: View {
    private struct BrowserApp: Identifiable {
        let id: String
        let name: String
        let url: URL
        let isDefault: Bool
    }

    @Environment(\.dismiss) var dismiss

    let account: CLIAccount
    let providerPath: String?
    var onDismiss: (() -> Void)?

    @StateObject private var coordinator = CLIAccountLoginCoordinator()
    @State private var apiKey = ""
    @State private var phase: LoginPhase = .options
    @State private var copiedURLHint = false
    @State private var authCodeInput = ""
    @State private var authCodeHint = ""
    @State private var deviceCodeCopied = false
    @State private var availableBrowsers: [BrowserApp] = []

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
        .onAppear {
            refreshAvailableBrowsers()
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
            // Primary: Browser OAuth (with browser chooser)
            if availableBrowsers.count > 1 {
                Menu {
                    ForEach(availableBrowsers) { browser in
                        Button {
                            loginWithBrowser(browserAppURL: browser.url)
                        } label: {
                            Text(browser.isDefault ? "\(browser.name) (default)" : browser.name)
                        }
                    }
                } label: {
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
                        Image(systemName: "chevron.down")
                    }
                    .padding(12)
                    .foregroundColor(.white)
                    .background(providerColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .menuStyle(.borderlessButton)
            } else {
                Button(action: { loginWithBrowser() }) {
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
            }

            if supportsDeviceCode {
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
            }

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
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.regular)
                        .opacity(isLoginRunning ? 1 : 0.35)
                    Text(coordinator.statusByAccount[account.id] ?? message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Complete the login in your browser...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let authURL = coordinator.authURLByAccount[account.id] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Login link")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(authURL.absoluteString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                if availableBrowsers.isEmpty {
                                    Link(destination: authURL) {
                                        Label("Open link", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Menu {
                                        ForEach(availableBrowsers) { browser in
                                            Button {
                                                open(authURL, with: browser.url)
                                            } label: {
                                                if browser.isDefault {
                                                    Text("\(browser.name) (default)")
                                                } else {
                                                    Text(browser.name)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Open in browser", systemImage: "globe")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .controlSize(.small)
                                }

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(authURL.absoluteString, forType: .string)
                                    copiedURLHint = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                        copiedURLHint = false
                                    }
                                } label: {
                                    Label("Copy link", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                if copiedURLHint {
                                    Text("Copied")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let deviceCode = coordinator.deviceCodeByAccount[account.id] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your device code")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(deviceCode)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(deviceCode, forType: .string)
                                    deviceCodeCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                        deviceCodeCopied = false
                                    }
                                } label: {
                                    Label(deviceCodeCopied ? "Copied" : "Copy code", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Text("Enter this code in the browser page above")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let output = coordinator.lastOutputByAccount[account.id], !output.isEmpty {
                        Text(output)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if shouldShowAuthCodeInput {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Authentication code")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Paste the code from browser or terminal", text: $authCodeInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            HStack(spacing: 8) {
                                Button {
                                    let pasted = NSPasteboard.general.string(forType: .string)?
                                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    guard !pasted.isEmpty else {
                                        authCodeHint = "Clipboard is empty"
                                        return
                                    }
                                    authCodeInput = pasted
                                    authCodeHint = "Code pasted"
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    guard coordinator.submitInteractiveInput(
                                        accountId: account.id,
                                        text: authCodeInput
                                    ) else {
                                        authCodeHint = "Unable to submit code"
                                        return
                                    }
                                    authCodeHint = "Code submitted"
                                    authCodeInput = ""
                                } label: {
                                    Label("Submit code", systemImage: "paperplane")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(authCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                if !authCodeHint.isEmpty {
                                    Text(authCodeHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }

            HStack(spacing: 8) {
                if isLoginRunning {
                    Button("Cancel") {
                        coordinator.cancelLogin(accountId: account.id)
                        phase = .options
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Back") {
                        phase = .options
                    }
                    .buttonStyle(.bordered)

                    Button(isLoginSuccess ? "OK, Close" : "Close") {
                        dismiss()
                        onDismiss?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

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

    private var supportsDeviceCode: Bool {
        account.provider != .claude
    }

    private var isLoginSuccess: Bool {
        guard let status = coordinator.statusByAccount[account.id] else { return false }
        return statusIsSuccess(status)
    }

    private var isLoginRunning: Bool {
        coordinator.isRunningByAccount[account.id] == true
    }

    private var shouldShowAuthCodeInput: Bool {
        if coordinator.awaitingInputByAccount[account.id] == true {
            return true
        }
        if case .polling = phase {
            return true
        }
        return false
    }

    private var dividerLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            Text("or").font(.caption).foregroundStyle(.tertiary)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
        }
    }

    private func statusIsSuccess(_ status: String) -> Bool {
        let lower = status.lowercased()
        return status == "Connected"
            || lower.contains("logged in")
            || lower.contains("login successful")
            || lower.contains("authenticated")
    }

    private func open(_ url: URL, with browserURL: URL) {
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }

    private func refreshAvailableBrowsers() {
        guard let probeURL = URL(string: "https://claude.ai") else { return }
        let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        let defaultBundleId = defaultAppURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)

        var seen: Set<String> = []
        var detected: [BrowserApp] = []
        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL) else { continue }
            let bundleId = bundle.bundleIdentifier ?? appURL.path
            guard seen.insert(bundleId).inserted else { continue }
            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            detected.append(
                BrowserApp(
                    id: bundleId,
                    name: displayName,
                    url: appURL,
                    isDefault: bundleId == defaultBundleId
                )
            )
        }
        availableBrowsers = detected.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
