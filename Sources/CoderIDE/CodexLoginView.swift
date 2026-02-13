import SwiftUI
import CoderEngine

struct CodexLoginView: View {
    @Environment(\.dismiss) var dismiss
    let codexPath: String
    let onDismiss: () -> Void
    
    @State private var useDeviceAuth = false
    @State private var apiKey = ""
    @State private var isPolling = false
    @State private var loginMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            loginHeader
            
            Divider()
            
            // Content
            if isPolling {
                pollingView
            } else {
                loginOptionsView
            }
        }
        .frame(width: 400)
        .background(DesignSystem.Colors.backgroundPrimary)
    }
    
    // MARK: - Login Header
    private var loginHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            
            Text("Accedi a Codex")
                .font(DesignSystem.Typography.title2)
            
            Text("Autenticati per usare Codex CLI")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondary)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.surface)
    }
    
    // MARK: - Polling View
    private var pollingView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            ProgressView()
                .scaleEffect(1.2)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(loginMessage)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.secondaryDark)
                
                Text("Attendere...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondary)
            }
            
            // Animated dots
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(0.8)
                }
            }
            .padding(.top, DesignSystem.Spacing.md)
        }
        .padding(DesignSystem.Spacing.xxl)
    }
    
    // MARK: - Login Options
    private var loginOptionsView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Browser login
            Button(action: loginWithBrowser) {
                HStack {
                    Image(systemName: "safari")
                        .font(.title3)
                    VStack(alignment: .leading) {
                        Text("Accedi con ChatGPT")
                            .font(DesignSystem.Typography.subheadline.bold())
                        Text("Apri il browser per autenticarti")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.primary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            }
            .buttonStyle(.plain)
            
            // Divider
            HStack {
                Rectangle()
                    .fill(DesignSystem.Colors.divider)
                    .frame(height: 1)
                Text("oppure")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondary)
                Rectangle()
                    .fill(DesignSystem.Colors.divider)
                    .frame(height: 1)
            }
            
            // Device code
            Button(action: loginWithDeviceCode) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.primary)
                    VStack(alignment: .leading) {
                        Text("Codice dispositivo")
                            .font(DesignSystem.Typography.subheadline.bold())
                            .foregroundStyle(DesignSystem.Colors.secondaryDark)
                        Text("Mostra codice nel terminale")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DesignSystem.Colors.secondary)
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // API Key section
            apiKeySection
            
            // Cancel button
            Button("Annulla", role: .cancel) {
                dismiss()
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondary)
            .padding(.top, DesignSystem.Spacing.md)
        }
        .padding(DesignSystem.Spacing.xl)
    }
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Oppure usa API Key")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            SecureField("openai_api_key", text: $apiKey)
                .textFieldStyle(.plain)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(DesignSystem.Colors.divider, lineWidth: 1)
                )
            
            Button("Accedi con API Key") {
                loginWithAPIKey()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(apiKey.isEmpty)
        }
    }
    
    // MARK: - Login Actions
    private func loginWithBrowser() {
        isPolling = true
        loginMessage = "Aprendo il browser..."
        Task { runLogin(args: []) }
    }
    
    private func loginWithDeviceCode() {
        isPolling = true
        loginMessage = "Mostra il codice nel terminale..."
        Task { runLogin(args: ["--device-auth"]) }
    }
    
    private func loginWithAPIKey() {
        guard !apiKey.isEmpty else { return }
        isPolling = true
        loginMessage = "Autenticazione in corso..."
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "--with-api-key"]
        process.standardInput = Pipe()
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            if let pipe = process.standardInput as? Pipe {
                pipe.fileHandleForWriting.write(apiKey.data(using: .utf8) ?? Data())
                try pipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            pollForLogin()
        } catch {
            isPolling = false
        }
    }
    
    private func runLogin(args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login"] + args
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            pollForLogin()
        } catch {
            isPolling = false
        }
    }
    
    private func pollForLogin() {
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                let newStatus = CodexDetector.detect(customPath: codexPath)
                if newStatus.isLoggedIn {
                    await MainActor.run {
                        isPolling = false
                        dismiss()
                        onDismiss()
                    }
                    return
                }
            }
            await MainActor.run {
                isPolling = false
                loginMessage = "Timeout. Riprova."
            }
        }
    }
}
