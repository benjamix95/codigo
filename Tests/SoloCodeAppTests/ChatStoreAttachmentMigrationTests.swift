import XCTest
@testable import CoderIDE

final class ChatStoreAttachmentMigrationTests: XCTestCase {
    func testDecodeLegacyImagePathsMigratesToImageAttachments() throws {
        let payload = """
        {
          "id":"\(UUID().uuidString)",
          "role":"user",
          "content":"legacy",
          "isStreaming":false,
          "imagePaths":["/tmp/a.png","/tmp/b.jpg"]
        }
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.imagePaths?.count, 2)
        XCTAssertEqual(decoded.attachments?.count, 2)
        XCTAssertEqual(decoded.attachments?.map(\.kind), [.image, .image])
        XCTAssertEqual(decoded.attachments?.map(\.localPath), ["/tmp/a.png", "/tmp/b.jpg"])
    }

    func testAttachmentRoundTripKeepsKindsAndMetadata() throws {
        let message = ChatMessage(
            role: .user,
            content: "attachments",
            attachments: [
                ChatAttachment(
                    kind: .image,
                    originalName: "img.png",
                    mimeType: "image/png",
                    localPath: "/tmp/img.png",
                    sizeBytes: 123
                ),
                ChatAttachment(
                    kind: .document,
                    originalName: "spec.pdf",
                    mimeType: "application/pdf",
                    localPath: "/tmp/spec.pdf",
                    sizeBytes: 456
                ),
                ChatAttachment(
                    kind: .file,
                    originalName: "archive.zip",
                    mimeType: "application/zip",
                    localPath: "/tmp/archive.zip",
                    sizeBytes: 789
                ),
            ]
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.attachments?.count, 3)
        XCTAssertEqual(decoded.attachments?.map(\.kind), [.image, .document, .file])
        XCTAssertEqual(decoded.attachments?.map(\.originalName), ["img.png", "spec.pdf", "archive.zip"])
    }
}
