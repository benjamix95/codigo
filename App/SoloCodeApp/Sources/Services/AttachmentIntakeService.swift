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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport
            .appendingPathComponent("Solo Code", isDirectory: true)
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

    /// Reads pasteboard metadata on the main thread (lightweight string
    /// reads only), then moves **all** data reads, image decoding,
    /// conversion and file I/O to a `.userInitiated` background queue so
    /// the user-interactive main thread never waits on lower-QoS work.
    static func attachmentsFromPasteboard(completion: @escaping ([ComposerAttachment]) -> Void) {
        let pasteboard = NSPasteboard.general

        // 1. Read file URLs via lightweight string property-lists (no
        //    cross-QoS deserialization).
        let fileURLs: [URL] = fileURLsFromPasteboard(pasteboard)

        // 2. Determine which image type is available (string comparison
        //    only – no data copying yet) so we can read the bytes off the
        //    main thread.
        let availableImageType: NSPasteboard.PasteboardType? =
            fileURLs.isEmpty ? firstAvailableImageType(on: pasteboard) : nil

        // 3. Move **everything** heavy – including `data(forType:)` – to
        //    `.userInitiated` QoS to avoid priority inversion.
        DispatchQueue.global(qos: .userInitiated).async {
            var attachments: [ComposerAttachment] = []

            if !fileURLs.isEmpty {
                for url in fileURLs {
                    if let attachment = importSingleURL(url) {
                        attachments.append(attachment)
                    }
                }
            }

            if attachments.isEmpty,
               let imageType = availableImageType,
               let imageData = pasteboard.data(forType: imageType),
               let image = NSImage(data: imageData),
               let url = saveImageToAttachmentStore(image),
               let attachment = importSingleURL(url) {
                attachments.append(attachment)
            }

            DispatchQueue.main.async {
                completion(attachments)
            }
        }
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

    /// Reads file URLs from the pasteboard using low-level property-list access
    /// instead of `readObjects(forClasses:)`, which internally dispatches
    /// deserialization work on the default QoS and causes priority inversion
    /// when the caller runs at user-interactive QoS.
    private static func fileURLsFromPasteboard(_ pasteboard: NSPasteboard) -> [URL] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString),
               url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }

    /// Returns the first available image pasteboard type **without** reading
    /// any data.  `availableType(from:)` only checks type metadata, so it
    /// is safe to call from the main (user-interactive) thread with no
    /// risk of priority inversion.
    private static func firstAvailableImageType(
        on pasteboard: NSPasteboard
    ) -> NSPasteboard.PasteboardType? {
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
        ]
        return pasteboard.availableType(from: imageTypes)
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
