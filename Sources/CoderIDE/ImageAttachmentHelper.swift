import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImageAttachmentHelper {
    static var attachmentsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoderIDE")
            .appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isSupportedImage(url: URL) -> Bool {
        let ext = (url.pathExtension as NSString).lowercased
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"].contains(ext)
    }

    static func isHeic(url: URL) -> Bool {
        let ext = (url.pathExtension as NSString).lowercased
        return ext == "heic" || ext == "heif"
    }

    /// Converts HEIC/HEIF to PNG and returns the new URL. For other formats, returns the original URL if supported.
    static func normalizeToPngIfNeeded(url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if isHeic(url: url) {
            return convertHeicToPng(url: url)
        }
        return isSupportedImage(url: url) ? url : nil
    }

    private static func convertHeicToPng(url: URL) -> URL? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        return saveToAttachments(nsImage: img)
    }

    /// Extracts image URL from drop provider (file URL or image data). Returns normalized PNG URL.
    static func imageURLFromDropProvider(_ provider: NSItemProvider) async -> URL? {
        if let url = await withCheckedContinuation({ (cont: CheckedContinuation<URL?, Never>) in
            provider.loadObject(ofClass: URL.self) { obj, _ in cont.resume(returning: obj as? URL) }
        }), url.isFileURL, FileManager.default.fileExists(atPath: url.path),
           let normalized = normalizeToPngIfNeeded(url: url) {
            return normalized
        }
        if let img = await withCheckedContinuation({ (cont: CheckedContinuation<NSImage?, Never>) in
            provider.loadObject(ofClass: NSImage.self) { obj, _ in cont.resume(returning: obj as? NSImage) }
        }), let saved = saveToAttachments(nsImage: img) {
            return saved
        }
        return nil
    }

    /// Reads image from NSPasteboard (screenshot, copy from browser) or file URL (copy from Finder).
    /// Saves to attachments folder and returns the file URL. Returns nil if no image found.
    static func imageURLFromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general

        // 1. Direct image data (screenshot, copy from browser)
        if let img = NSImage(pasteboard: pasteboard) {
            return saveToAttachments(nsImage: img)
        }

        // 2. File URL (copy from Finder) — convert HEIC to PNG
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path),
           let result = normalizeToPngIfNeeded(url: url) {
            return result
        }

        // 3. TIFF/PNG data
        if let tiff = pasteboard.data(forType: .tiff),
           let img = NSImage(data: tiff) {
            return saveToAttachments(nsImage: img)
        }
        if let png = pasteboard.data(forType: .png),
           let img = NSImage(data: png) {
            return saveToAttachments(nsImage: img)
        }

        return nil
    }

    private static func saveToAttachments(nsImage: NSImage) -> URL? {
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        let name = UUID().uuidString + ".png"
        let url = attachmentsDirectory.appendingPathComponent(name)
        do {
            try pngData.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
