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

            Text("Accedi a Codex")
                .font(.title3)

            Text("Autenticati per usare Codex CLI")
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
            Text("Attendere...")
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
                        Text("Accedi con ChatGPT")
                            .font(.subheadline.weight(.medium))
                        Text("Apri il browser per autenticarti")
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
                Text("oppure").font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 1)
            }

            Button(action: loginWithDeviceCode) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codice dispositivo")
                            .font(.subheadline.weight(.medium))
                        Text("Mostra codice nel terminale")
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
                Text("Oppure usa API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                SecureField("openai_api_key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Accedi con API Key") { loginWithAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)
            }

            Button("Annulla", role: .cancel) {
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
        loginMessage = "Aprendo il browser..."
        runLogin(args: [])
    }

    private func loginWithDeviceCode() {
        isPolling = true
        loginMessage = "Mostra il codice nel terminale..."
        runLogin(args: ["--device-auth"])
    }

    private func loginWithAPIKey() {
        guard !apiKey.isEmpty else { return }
        isPolling = true
        loginMessage = "Autenticazione in corso..."

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "--with-api-key"]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = nil
        process.standardError = nil
        process.environment = CodexDetector.shellEnvironment()

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((apiKey + "\n").data(using: .utf8) ?? Data())
            try inputPipe.fileHandleForWriting.close()
        } catch {
            isPolling = false
            return
        }

        let capturedPath = codexPath
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    startPolling(codexPath: capturedPath)
                } else {
                    isPolling = false
                    loginMessage = "Login fallito. Verifica API key e riprova."
                }
            }
        }
    }

    private func runLogin(args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login"] + args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.environment = CodexDetector.shellEnvironment()

        do {
            try process.run()
        } catch {
            isPolling = false
            return
        }

        // Read output asynchronously — open login URLs in the system browser
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if let regex = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text),
               let url = URL(string: String(text[range])) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }

        let capturedPath = codexPath
        process.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    startPolling(codexPath: capturedPath)
                } else {
                    isPolling = false
                    loginMessage = "Login non completato. Riprova."
                }
            }
        }
    }

    private func startPolling(codexPath: String) {
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                let ready = await Task.detached {
                    CodexDetector.detect(customPath: codexPath).isLoggedIn
                }.value
                if ready {
                    isPolling = false
                    dismiss()
                    onDismiss()
                    return
                }
            }
            isPolling = false
            loginMessage = "Timeout. Riprova."
        }
    }
}
