import XCTest
import CoderEngine

final class ProviderAttachmentCapabilityTests: XCTestCase {
    func testDefaultAttachmentCapabilitiesAreNone() {
        let provider = MockAttachmentProvider()
        XCTAssertEqual(provider.attachmentCapabilities, .none)
    }

    func testAttachmentFallbackRoutesOnlyImagesToLegacySend() async throws {
        let provider = MockAttachmentProvider()
        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        let attachments: [LLMAttachment] = [
            LLMAttachment(
                kind: .image,
                url: URL(fileURLWithPath: "/tmp/image.png"),
                mimeType: "image/png",
                filename: "image.png",
                sizeBytes: 100
            ),
            LLMAttachment(
                kind: .document,
                url: URL(fileURLWithPath: "/tmp/spec.pdf"),
                mimeType: "application/pdf",
                filename: "spec.pdf",
                sizeBytes: 200
            ),
            LLMAttachment(
                kind: .file,
                url: URL(fileURLWithPath: "/tmp/archive.zip"),
                mimeType: "application/zip",
                filename: "archive.zip",
                sizeBytes: 300
            ),
        ]

        let stream = try await provider.send(
            prompt: "test",
            context: context,
            attachments: attachments
        )
        for try await _ in stream {
            // no-op
        }

        XCTAssertEqual(provider.capturedImageURLs?.count, 1)
        XCTAssertEqual(provider.capturedImageURLs?.first?.lastPathComponent, "image.png")
    }
}

private final class MockAttachmentProvider: LLMProvider, @unchecked Sendable {
    let id = "mock-attachment-provider"
    let displayName = "Mock Attachment Provider"
    var capturedImageURLs: [URL]?

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        capturedImageURLs = imageURLs
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
