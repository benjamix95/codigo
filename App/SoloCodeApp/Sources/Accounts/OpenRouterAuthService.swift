import Foundation
import CryptoKit

/// Network and PKCE helpers for OpenRouter OAuth, extracted from `OpenRouterLoginView`.
enum OpenRouterAuthService {

    // MARK: - Code Exchange

    /// Exchanges an OAuth authorization code for an OpenRouter API key.
    /// - Parameters:
    ///   - code: The authorization code received from the callback.
    ///   - verifier: The PKCE code verifier used when the auth session started.
    /// - Returns: The API key string on success.
    static func exchangeCodeForKey(code: String, verifier: String) async throws -> String {
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
                NSLocalizedDescriptionKey: "Response does not contain 'key'"
            ])
        }

        return key
    }

    // MARK: - PKCE Helpers

    /// Generates a cryptographically random PKCE code verifier (Base64-URL encoded).
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Derives the S256 code challenge from a given code verifier.
    static func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
