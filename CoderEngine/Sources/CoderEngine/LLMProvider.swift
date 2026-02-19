import Foundation

/// Protocollo base per i provider LLM
public protocol LLMProvider: Sendable {
    /// Identificatore univoco
    var id: String { get }
    
    /// Nome visualizzato in UI
    var displayName: String { get }
    
    /// Verifica se il provider è autenticato/configurato
    func isAuthenticated() -> Bool
    
    /// Invia un prompt e riceve risposta in streaming. Opzionalmente include immagini per modelli multimodali.
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error>
}
