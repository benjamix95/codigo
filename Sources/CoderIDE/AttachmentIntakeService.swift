import AppKit
import Foundation
import UniformTypeIdentifiers

struct ComposerAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: ChatAttachmentKind
    let url: URL
    let originalName: String
    let mimeType: String?
    let sizeBytes: Int64?

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        url: URL,
        originalName: String,
        mimeType: String?,
        sizeBytes: Int64?
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.originalName = originalName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

enum AttachmentIntakeService {
    static let maxAttachmentsPerMessage = 10
    static let maxAttachmentSizeBytes: Int64 = 25 * 1024 * 1024

    static var attachmentsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("Codigo", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importURLs(
        _ urls: [URL],
        existingCount: Int
    ) -> (accepted: [ComposerAttachment], rejected: [String]) {
        var accepted: [ComposerAttachment] = []
        var rejected: [String] = []
        var currentCount = existingCount

        for url in urls {
            if currentCount >= maxAttachmentsPerMessage {
                rejected.append("Limit reached: maximum \(maxAttachmentsPerMessage) attachments per message.")
                break
            }

            guard let attachment = importSingleURL(url) else {
                rejected.append("Allegato non supportato: \(url.lastPathComponent)")
                continue
            }

            if let size = attachment.sizeBytes, size > maxAttachmentSizeBytes {
                rejected.append("File troppo grande (\(attachment.originalName)). Max 25MB.")
                continue
            }

            accepted.append(attachment)
            currentCount += 1
        }

        return (accepted, rejected)
    }

    static func attachmentFromDropProvider(_ provider: NSItemProvider) async -> ComposerAttachment? {
        if let url = await withCheckedContinuation({ (cont: CheckedContinuation<URL?, Never>) in
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                cont.resume(returning: obj)
            }
        }), url.isFileURL {
            return importSingleURL(url)
        }

        if let image = await withCheckedContinuation({ (cont: CheckedContinuation<NSImage?, Never>) in
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                cont.resume(returning: obj as? NSImage)
            }
        }), let tempURL = saveImageToAttachmentStore(image) {
            return importSingleURL(tempURL)
        }

        return nil
    }

    static func attachmentsFromPasteboard() -> [ComposerAttachment] {
        let pasteboard = NSPasteboard.general
        var attachments: [ComposerAttachment] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where url.isFileURL {
                if let attachment = importSingleURL(url) {
                    attachments.append(attachment)
                }
            }
            if !attachments.isEmpty {
                return attachments
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let url = saveImageToAttachmentStore(image),
           let attachment = importSingleURL(url) {
            attachments.append(attachment)
        }

        return attachments
    }

    static func classify(url: URL) -> ChatAttachmentKind {
        if ImageAttachmentHelper.isSupportedImage(url: url) {
            return .image
        }
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if type.conforms(to: .pdf)
                || type.conforms(to: .plainText)
                || type.conforms(to: .rtf)
                || type.conforms(to: .html)
                || type.conforms(to: .xml)
                || type.conforms(to: .json)
                || type.conforms(to: .spreadsheet)
                || type.conforms(to: .presentation)
                || type.conforms(to: .text) {
                return .document
            }
        }
        return .file
    }

    static func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return nil }
        return UTType(filenameExtension: ext)?.preferredMIMEType
    }

    private static func importSingleURL(_ sourceURL: URL) -> ComposerAttachment? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let kind = classify(url: sourceURL)
        let normalizedURL: URL
        if kind == .image {
            guard let normalized = ImageAttachmentHelper.normalizeToPngIfNeeded(url: sourceURL) else {
                return nil
            }
            normalizedURL = normalized
        } else {
            normalizedURL = sourceURL
        }

        guard let storedURL = persistForComposer(url: normalizedURL) else {
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let size = attrs?[.size] as? NSNumber
        return ComposerAttachment(
            kind: kind,
            url: storedURL,
            originalName: sourceURL.lastPathComponent,
            mimeType: mimeType(for: storedURL),
            sizeBytes: size?.int64Value
        )
    }

    private static func persistForComposer(url: URL) -> URL? {
        let src = url.standardizedFileURL
        let base = attachmentsDirectory.standardizedFileURL
        if src.path.hasPrefix(base.path) {
            return src
        }

        let ext = src.pathExtension
        let filename = ext.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(ext)"
        let dest = base.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private static func saveImageToAttachmentStore(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let url = attachmentsDirectory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try pngData.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
