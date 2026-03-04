import Foundation

// MARK: - Extension XPC Protocol

/// Protocollo XPC per la comunicazione con plugin in processi separati.
/// Definisce il contratto bidirezionale host ↔ plugin.
@objc protocol ExtensionXPCPluginProtocol {
    /// Inizializza il plugin con la configurazione serializzata.
    func initialize(
        configurationData: Data,
        withReply reply: @escaping (Data?, Error?) -> Void
    )

    /// Esegue un tool con il payload serializzato.
    func executeTool(
        name: String,
        payloadData: Data,
        withReply reply: @escaping (Data?, Error?) -> Void
    )

    /// Scarica il plugin e rilascia le risorse.
    func shutdown(withReply reply: @escaping (Error?) -> Void)

    /// Verifica che il plugin sia ancora attivo (heartbeat).
    func ping(withReply reply: @escaping (Bool) -> Void)
}

/// Protocollo XPC inverso: consente al plugin di comunicare con l'host.
@objc protocol ExtensionXPCHostProtocol {
    /// Il plugin richiede una capability all'host.
    func requestCapability(
        _ capability: String,
        withReply reply: @escaping (Bool) -> Void
    )

    /// Il plugin invia un log/evento all'host.
    func reportEvent(
        level: String,
        message: String,
        metadata: Data
    )
}

// MARK: - XPC Data Models

/// Configurazione inviata al plugin via XPC.
struct XPCPluginConfiguration: Codable, Sendable {
    let pluginId: String
    let workspaceRoots: [String]
    let grantedCapabilities: [String]
    let timeout: TimeInterval

    static let defaultTimeout: TimeInterval = 30
}

/// Risposta del plugin serializzata via XPC.
struct XPCToolResult: Codable, Sendable {
    let output: String
    let metadata: [String: String]
    let durationMs: Int

    func toToolResponse() -> ExtensionToolResponse {
        ExtensionToolResponse(output: output, metadata: metadata)
    }
}

/// Errori specifici della comunicazione XPC.
enum XPCError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case timeout(pluginId: String, seconds: TimeInterval)
    case pluginCrashed(pluginId: String)
    case serializationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connessione XPC fallita: \(reason)"
        case .timeout(let pluginId, let seconds):
            return "Plugin \(pluginId) timeout dopo \(Int(seconds))s"
        case .pluginCrashed(let pluginId):
            return "Plugin \(pluginId) crash rilevato"
        case .serializationFailed(let reason):
            return "Serializzazione XPC fallita: \(reason)"
        case .invalidResponse:
            return "Risposta XPC non valida"
        }
    }
}
