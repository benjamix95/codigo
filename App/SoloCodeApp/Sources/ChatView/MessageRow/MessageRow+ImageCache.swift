import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI
/// Loads an image thumbnail asynchronously and caches the result.
/// Click opens a full-size Quick Look panel; context menu provides copy, save, and reveal.
struct CachedThumbnailView: View {
    let path: String
    let width: CGFloat
    let height: CGFloat

    @State private var loadedImage: NSImage?
    @State private var loadFailed = false
    @State private var isHovered = false
    @State private var showFullPreview = false

    var body: some View {
        ZStack {
            Group {
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if loadFailed {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: width, height: height)
            .clipped()

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(isHovered ? 0.2 : 0))
                .frame(width: width, height: height)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        Text("Preview")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .opacity(isHovered ? 1 : 0)
                )
        }
        .frame(width: width, height: height)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08),
                    lineWidth: isHovered ? 1.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture {
            openImageInPreview()
        }
        .popover(isPresented: $showFullPreview, arrowEdge: .bottom) {
            imageFullPreviewPopover
        }
        .contextMenu {
            Button { openImageInPreview() } label: {
                Label("Open in Preview", systemImage: "eye")
            }
            Button { showFullPreview = true } label: {
                Label("Quick Look", systemImage: "magnifyingglass")
            }
            Divider()
            Button { copyImageToClipboard() } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            Button { saveImageAs() } label: {
                Label("Save As…", systemImage: "square.and.arrow.down")
            }
            Divider()
            Button { revealInFinder() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .task(id: path) {
            if let cached = MessageImageCache.shared.image(for: path) {
                loadedImage = cached
                return
            }
            // Load raw data off-main to avoid NSImage Sendable availability warnings.
            let imageData: Data? = await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return try? Data(contentsOf: url)
            }.value
            if let data = imageData, let img = NSImage(data: data) {
                MessageImageCache.shared.setImage(img, for: path)
                loadedImage = img
            } else {
                loadFailed = true
            }
        }
    }

    @ViewBuilder
    private var imageFullPreviewPopover: some View {
        if let img = loadedImage {
            let imgSize = img.size
            let maxW: CGFloat = 600
            let maxH: CGFloat = 500
            let scale = min(maxW / max(imgSize.width, 1), maxH / max(imgSize.height, 1), 1.0)
            let displayW = imgSize.width * scale
            let displayH = imgSize.height * scale

            VStack(spacing: 8) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: max(displayW, 200), height: max(displayH, 150))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 12) {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button { openImageInPreview() } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button { saveImageAs() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button { copyImageToClipboard() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 220)
        }
    }

    private func openImageInPreview() {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func copyImageToClipboard() {
        guard let img = loadedImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        let url = URL(fileURLWithPath: path) as NSURL
        pb.writeObjects([url])
    }

    private func saveImageAs() {
        let panel = NSSavePanel()
        let fileName = (path as NSString).lastPathComponent
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png, .jpeg]
        panel.begin { result in
            guard result == .OK, let dest = panel.url else { return }
            try? FileManager.default.copyItem(
                at: URL(fileURLWithPath: path),
                to: dest
            )
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

/// Simple in-memory image cache for user-attached message thumbnails.
final class MessageImageCache: @unchecked Sendable {
    static let shared = MessageImageCache()
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private let maxEntries = 50

    func image(for path: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[path]
    }

    func setImage(_ image: NSImage, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        if cache.count >= maxEntries {
            // Evict oldest (arbitrary) entry
            if let first = cache.keys.first { cache.removeValue(forKey: first) }
        }
        cache[path] = image
    }
}
