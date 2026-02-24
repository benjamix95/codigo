import Foundation

public enum LLMAttachmentKind: String, Codable, Sendable {
    case image
    case document
    case file
}

public struct LLMAttachment: Codable, Equatable, Sendable {
    public let kind: LLMAttachmentKind
    public let url: URL
    public let mimeType: String?
    public let filename: String
    public let sizeBytes: Int64?

    public init(
        kind: LLMAttachmentKind,
        url: URL,
        mimeType: String? = nil,
        filename: String,
        sizeBytes: Int64? = nil
    ) {
        self.kind = kind
        self.url = url
        self.mimeType = mimeType
        self.filename = filename
        self.sizeBytes = sizeBytes
    }
}

public struct ProviderAttachmentCapabilities: Equatable, Sendable {
    public let nativeImage: Bool
    public let nativeDocument: Bool
    public let nativeFile: Bool

    public init(
        nativeImage: Bool,
        nativeDocument: Bool,
        nativeFile: Bool
    ) {
        self.nativeImage = nativeImage
        self.nativeDocument = nativeDocument
        self.nativeFile = nativeFile
    }

    public static let none = ProviderAttachmentCapabilities(
        nativeImage: false,
        nativeDocument: false,
        nativeFile: false
    )
}

/// Protocollo base per i provider LLM
public protocol LLMProvider: Sendable {
    /// Identificatore univoco
    var id: String { get }
    
    /// Nome visualizzato in UI
    var displayName: String { get }

    /// Capability native dichiarate dal provider per allegati multimodali.
    var attachmentCapabilities: ProviderAttachmentCapabilities { get }
    
    /// Verifica se il provider è autenticato/configurato
    func isAuthenticated() -> Bool
    
    /// Invia un prompt e riceve risposta in streaming. Opzionalmente include immagini per modelli multimodali.
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error>

    /// Nuovo canale allegati tipizzati.
    func send(
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

public extension LLMProvider {
    var attachmentCapabilities: ProviderAttachmentCapabilities { .none }

    func send(
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let imageURLs = attachments?.compactMap { attachment -> URL? in
            attachment.kind == .image ? attachment.url : nil
        }
        return try await send(prompt: prompt, context: context, imageURLs: imageURLs)
    }
}
