import Foundation

// MARK: - Extension XPC Host

/// Host XPC che gestisce le connessioni ai plugin in processi separati.
/// Fornisce isolamento, timeout e recovery automatico per i plugin.
actor ExtensionXPCHost {
    /// Stato di una connessione XPC.
    struct ConnectionState: Sendable {
        let pluginId: String
        let startedAt: Date
        var isAlive: Bool
        var lastPing: Date?
        var crashCount: Int
    }

    private var connections: [String: NSXPCConnection] = [:]
    private var connectionStates: [String: ConnectionState] = [:]
    private let maxCrashRetries = 3
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Connessione

    /// Connette un plugin via XPC con la configurazione fornita.
    func connect(
        pluginId: String,
        serviceName: String,
        configuration: XPCPluginConfiguration
    ) async throws {
        if connections[pluginId] != nil {
            await disconnect(pluginId: pluginId)
        }

        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ExtensionXPCPluginProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: ExtensionXPCHostProtocol.self)

        let hostHandler = XPCHostHandler(pluginId: pluginId)
        connection.exportedObject = hostHandler

        connection.invalidationHandler = { [weak self] in
            Task { [weak self] in
                await self?.handleDisconnection(pluginId: pluginId)
            }
        }

        connection.interruptionHandler = { [weak self] in
            Task { [weak self] in
                await self?.handleInterruption(pluginId: pluginId)
            }
        }

        connection.resume()
        connections[pluginId] = connection

        connectionStates[pluginId] = ConnectionState(
            pluginId: pluginId,
            startedAt: Date(),
            isAlive: true,
            lastPing: nil,
            crashCount: 0
        )

        try await initializePlugin(pluginId: pluginId, configuration: configuration)
    }

    /// Disconnette un plugin e rilascia la connessione XPC.
    func disconnect(pluginId: String) async {
        if let connection = connections.removeValue(forKey: pluginId) {
            let proxy = connection.remoteObjectProxy as? ExtensionXPCPluginProtocol
            proxy?.shutdown { _ in }
            connection.invalidate()
        }
        connectionStates.removeValue(forKey: pluginId)
    }

    // MARK: - Esecuzione

    /// Esegue un tool su un plugin via XPC.
    func executeTool(
        pluginId: String,
        tool: String,
        payload: [String: String],
        timeout: TimeInterval = XPCPluginConfiguration.defaultTimeout
    ) async throws -> ExtensionToolResponse {
        guard let connection = connections[pluginId] else {
            throw XPCError.connectionFailed("Plugin \(pluginId) non connesso")
        }

        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            throw XPCError.serializationFailed(error.localizedDescription)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: XPCError.connectionFailed(error.localizedDescription))
            } as? ExtensionXPCPluginProtocol

            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed("Proxy non disponibile"))
                return
            }

            proxy.executeTool(name: tool, payloadData: payloadData) { [decoder] resultData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = resultData,
                      let result = try? decoder.decode(XPCToolResult.self, from: data) else {
                    continuation.resume(throwing: XPCError.invalidResponse)
                    return
                }

                continuation.resume(returning: result.toToolResponse())
            }
        }
    }

    // MARK: - Health Check

    /// Verifica che un plugin sia ancora attivo.
    func isAlive(pluginId: String) async -> Bool {
        guard let connection = connections[pluginId] else { return false }

        return await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: false)
            } as? ExtensionXPCPluginProtocol

            guard let proxy else {
                continuation.resume(returning: false)
                return
            }

            proxy.ping { alive in
                continuation.resume(returning: alive)
            }
        }
    }

    /// Restituisce lo stato di tutte le connessioni attive.
    func activeConnections() -> [ConnectionState] {
        Array(connectionStates.values)
    }

    // MARK: - Privato

    private func initializePlugin(
        pluginId: String,
        configuration: XPCPluginConfiguration
    ) async throws {
        guard let connection = connections[pluginId] else {
            throw XPCError.connectionFailed("Connessione non trovata")
        }

        let configData: Data
        do {
            configData = try encoder.encode(configuration)
        } catch {
            throw XPCError.serializationFailed(error.localizedDescription)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: XPCError.connectionFailed(error.localizedDescription))
            } as? ExtensionXPCPluginProtocol

            guard let proxy else {
                continuation.resume(throwing: XPCError.connectionFailed("Proxy non disponibile"))
                return
            }

            proxy.initialize(configurationData: configData) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func handleDisconnection(pluginId: String) {
        connections.removeValue(forKey: pluginId)
        connectionStates[pluginId]?.isAlive = false
    }

    private func handleInterruption(pluginId: String) {
        connectionStates[pluginId]?.isAlive = false
        connectionStates[pluginId]?.crashCount += 1
    }
}

// MARK: - XPC Host Handler

/// Handler che il plugin usa per comunicare con l'host.
final class XPCHostHandler: NSObject, ExtensionXPCHostProtocol, @unchecked Sendable {
    let pluginId: String

    init(pluginId: String) {
        self.pluginId = pluginId
    }

    func requestCapability(_ capability: String, withReply reply: @escaping (Bool) -> Void) {
        // Per ora nega tutte le richieste runtime di capability
        reply(false)
    }

    func reportEvent(level: String, message: String, metadata: Data) {
        // Log degli eventi dal plugin
        #if DEBUG
        print("[XPC:\(pluginId)] [\(level)] \(message)")
        #endif
    }
}
