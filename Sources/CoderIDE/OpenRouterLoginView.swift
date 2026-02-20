import SwiftUI
import AuthenticationServices
import CryptoKit

struct OpenRouterLoginView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var apiKey: String
    let onSuccess: () -> Void

    @State private var manualKey = ""
    @State private var isAuthenticating = false
    @State private var authMessage = ""
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isAuthenticating {
                progressView
            } else {
                optionsView
            }
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 36))
                .foregroundStyle(Color.orange)

            Text("Accedi a OpenRouter")
                .font(.title3.weight(.semibold))

            Text("Autentica per usare 400+ modelli AI senza API key manuale")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text(authMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)

                Button("Riprova") {
                    isAuthenticating = false
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
    }

    // MARK: - Options

    private var optionsView: some View {
        VStack(spacing: 16) {
            Button(action: loginWithOAuth) {
                HStack {
                    Image(systemName: "safari")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accedi con OpenRouter")
                            .font(.subheadline.weight(.medium))
                        Text("Login sicuro via browser (OAuth PKCE)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(12)
                .foregroundColor(.white)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            HStack {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
                Text("oppure").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Inserisci API Key manualmente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                SecureField("sk-or-...", text: $manualKey)
                    .textFieldStyle(.roundedBorder)

                Button("Salva API Key") { saveManualKey() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(manualKey.isEmpty)
            }

            Button("Annulla", role: .cancel) { dismiss() }
                .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - OAuth PKCE

    private func loginWithOAuth() {
        isAuthenticating = true
        authMessage = "Apertura browser..."
        errorMessage = nil

        let verifier = generateCodeVerifier()
        guard let challenge = generateCodeChallenge(from: verifier) else {
            errorMessage = "Errore generazione code challenge"
            isAuthenticating = false
            return
        }

        let callbackScheme = "codigo"
        let callbackURL = "\(callbackScheme)://oauth/callback"

        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            errorMessage = "URL autenticazione non valido"
            isAuthenticating = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin {
                DispatchQueue.main.async {
                    isAuthenticating = false
                    authSession = nil
                }
                return
            }
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    authMessage = "Errore"
                    isAuthenticating = false
                    authSession = nil
                }
                return
            }
            guard let callbackURL = callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async {
                    errorMessage = "Codice di autorizzazione non ricevuto"
                    authMessage = "Errore"
                    isAuthenticating = false
                    authSession = nil
                }
                return
            }

            DispatchQueue.main.async {
                authMessage = "Scambio codice per API key..."
            }
            exchangeCodeForKey(code: code, verifier: verifier)
        }

        session.presentationContextProvider = OpenRouterAuthContext.shared
        session.prefersEphemeralWebBrowserSession = false
        authSession = session

        if !session.start() {
            errorMessage = "Impossibile avviare sessione di autenticazione"
            isAuthenticating = false
            authSession = nil
        }
    }

    private func exchangeCodeForKey(code: String, verifier: String) {
        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/auth/keys")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: String] = ["code": code, "code_verifier": verifier]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(statusCode)"
                    ])
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let key = json["key"] as? String else {
                    throw URLError(.cannotParseResponse, userInfo: [
                        NSLocalizedDescriptionKey: "Risposta non contiene 'key'"
                    ])
                }

                await MainActor.run {
                    apiKey = key
                    isAuthenticating = false
                    authSession = nil
                    onSuccess()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Scambio fallito: \(error.localizedDescription)"
                    authMessage = "Errore"
                    isAuthenticating = false
                    authSession = nil
                }
            }
        }
    }

    // MARK: - Manual Key

    private func saveManualKey() {
        apiKey = manualKey
        onSuccess()
        dismiss()
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Auth Presentation Context

final class OpenRouterAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OpenRouterAuthContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
