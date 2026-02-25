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

/// Base protocol for LLM providers.
public protocol LLMProvider: Sendable {
    /// Unique identifier.
    var id: String { get }
    
    /// Display name shown in UI.
    var displayName: String { get }

    /// Native multimodal attachment capabilities declared by the provider.
    var attachmentCapabilities: ProviderAttachmentCapabilities { get }
    
    /// Returns whether the provider is authenticated/configured.
    func isAuthenticated() -> Bool
    
    /// Sends a prompt and returns a streaming response. Can include images for multimodal models.
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error>

    /// Typed attachment channel.
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
