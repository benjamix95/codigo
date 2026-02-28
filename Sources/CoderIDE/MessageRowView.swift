import AppKit
import CoderEngine
import SwiftUI

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    var streamingReasoningText: String? = nil
    var showStreamingBar: Bool = true
    let onFileClicked: (String) -> Void
    var onRestoreCheckpoint: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var canRewind: Bool = false
    var hasCheckpointForRestore: Bool = false
    var showTopDivider: Bool = false
    @State private var isHovered = false
    @State private var didCopyMessage = false
    @State private var hoverTask: Task<Void, Never>?
    private let userRowMaxWidth: CGFloat = 620
    private let assistantRowMaxWidth: CGFloat = 920
    private let userImageThumbWidth: CGFloat = 80
    private let userImageThumbHeight: CGFloat = 56

    private var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    private var shouldShowStreamingBar: Bool {
        showStreamingBar && isActivelyStreaming
    }

    private var isUser: Bool { message.role == .user }
    private var rowMaxWidth: CGFloat { isUser ? userRowMaxWidth : assistantRowMaxWidth }
    private var contentMaxWidth: CGFloat { isUser ? 560 : 860 }
    private var shouldShowCopyAction: Bool { Self.shouldShowCopyAction(for: message) }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            if showTopDivider {
                messageDivider
            }
            if isUser {
                userHeader
            } else {
                assistantHeader
            }
            HStack(alignment: .top, spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                messageContent
                if !isUser { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: rowMaxWidth, alignment: isUser ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 40_000_000) // 40ms debounce
                    guard !Task.isCancelled else { return }
                    isHovered = true
                }
            } else {
                hoverTask?.cancel()
                hoverTask = nil
                isHovered = false
            }
        }
    }

    // MARK: - Message Divider

    private var messageDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .frame(height: 0.5)
            .frame(maxWidth: rowMaxWidth)
            .padding(.bottom, 16)
    }

    // MARK: - User Header

    private var userHeader: some View {
        HStack(spacing: 5) {
            Spacer(minLength: 0)
            if canRewind {
                Button {
                    onRestoreCheckpoint?()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.quaternary)
                .help(
                    hasCheckpointForRestore
                        ? "Restore chat and files from this point"
                        : "Restore chat from this point"
                )
                .accessibilityLabel("Restore checkpoint")
            }
            Text("You")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .padding(.trailing, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Assistant Header

    private var assistantHeader: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(modeColor.opacity(0.5))
                .frame(width: 5, height: 5)
            Text("Codigo")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Message Content

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if isUser {
                if let attachments = message.attachments, !attachments.isEmpty {
                    userAttachmentsRow(attachments: attachments)
                } else if let paths = message.imagePaths, !paths.isEmpty {
                    userMessageImagesRow(paths: paths)
                }
            }
            if isUser {
                MarkdownContentView(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading,
                    isStreaming: false,
                    aggressiveSanitization: false,
                    fillWidth: false
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DesignSystem.Colors.chatUserBubbleFill)
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: contentMaxWidth, alignment: .trailing)
                if shouldShowCopyAction {
                    messageActionsRow
                }
            } else {
                // Thinking block — show live reasoning during streaming, or persisted reasoning on historical messages
                if let reasoning = isActivelyStreaming ? streamingReasoningText : message.reasoningText,
                   !reasoning.isEmpty
                {
                    ThinkingBlockView(text: reasoning, isLiveStreaming: isActivelyStreaming)
                        .padding(.bottom, 8)
                }
                // Main content
                MarkdownContentView(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading,
                    isStreaming: isActivelyStreaming
                )
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.vertical, 4)
                // Streaming bar
                if shouldShowStreamingBar { streamingBar }
                if shouldShowCopyAction {
                    messageActionsRow
                }
            }
        }
    }

    @ViewBuilder
    private func userAttachmentsRow(attachments: [ChatAttachment]) -> some View {
        let imagePaths = attachments
            .filter { $0.kind == .image }
            .map(\.localPath)
        if !imagePaths.isEmpty {
            userMessageImagesRow(paths: imagePaths)
        }
        let nonImage = attachments.filter { $0.kind != .image }
        if !nonImage.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nonImage) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.kind == .document ? "doc.text" : "paperclip")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(attachment.originalName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let size = attachment.sizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.system(size: 9.5, weight: .regular))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        )
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Streaming Bar

    private var messageActionsRow: some View {
        HStack(spacing: 2) {
            Button {
                copyMessageToClipboard()
            } label: {
                Image(systemName: didCopyMessage ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(didCopyMessage ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(didCopyMessage ? "Copied" : "Copy message")
            .accessibilityLabel(didCopyMessage ? "Copied" : "Copy message")
            .animation(.easeOut(duration: 0.15), value: didCopyMessage)

            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reply")
                .accessibilityLabel("Reply")
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete message")
                .accessibilityLabel("Delete message")
            }
        }
        .opacity(isHovered ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.trailing, isUser ? 6 : 0)
        .padding(.leading, isUser ? 0 : 2)
    }

    private func copyMessageToClipboard() {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopyMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyMessage = false
        }
    }

    static func shouldShowCopyAction(for message: ChatMessage) -> Bool {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch message.role {
        case .user:
            return true
        case .assistant:
            return !message.isStreaming
        }
    }

    private var streamingBar: some View {
        let status = streamingStatusText.isEmpty ? "Thinking" : streamingStatusText
        return HStack(spacing: 6) {
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textShimmer(active: true)
            if let detail = streamingDetailText, !detail.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textShimmer(active: true)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - User Images

    @ViewBuilder
    private func userMessageImagesRow(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    CachedThumbnailView(
                        path: path,
                        width: userImageThumbWidth,
                        height: userImageThumbHeight
                    )
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.bottom, 4)
    }
}

/// Loads an image thumbnail asynchronously and caches the result.
/// Supports context menu for Quick Look, copy, and save.
private struct CachedThumbnailView: View {
    let path: String
    let width: CGFloat
    let height: CGFloat

    @State private var loadedImage: NSImage?
    @State private var loadFailed = false
    @State private var isShowingQuickLook = false
    @State private var isHovered = false

    var body: some View {
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
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(isHovered ? 0.15 : 0))
                .overlay(
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isHovered ? 0.9 : 0)
                )
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            openImageInPreview()
        }
        .contextMenu {
            Button {
                openImageInPreview()
            } label: {
                Label("Open", systemImage: "eye")
            }
            Button {
                copyImageToClipboard()
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            Button {
                saveImageToDesktop()
            } label: {
                Label("Save to Desktop", systemImage: "square.and.arrow.down")
            }
            Divider()
            Button {
                revealInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .task(id: path) {
            if let cached = MessageImageCache.shared.image(for: path) {
                loadedImage = cached
                return
            }
            let result = await Task.detached(priority: .utility) {
                guard FileManager.default.fileExists(atPath: path) else { return nil as NSImage? }
                return NSImage(contentsOf: URL(fileURLWithPath: path))
            }.value
            if let img = result {
                MessageImageCache.shared.setImage(img, for: path)
                loadedImage = img
            } else {
                loadFailed = true
            }
        }
    }

    private func openImageInPreview() {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func copyImageToClipboard() {
        guard let img = loadedImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        let url = URL(fileURLWithPath: path) as NSURL
        pb.writeObjects([url])
    }

    private func saveImageToDesktop() {
        let panel = NSSavePanel()
        let fileName = (path as NSString).lastPathComponent
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
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
private final class MessageImageCache: @unchecked Sendable {
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

// MARK: - Thinking Block (LLM reasoning — inline Cursor-style)

struct ThinkingBlockView: View {
    let text: String
    var isLiveStreaming: Bool = false
    @State private var isExpanded = false
    private let contentMaxWidth: CGFloat = 860

    @Environment(\.colorScheme) private var colorScheme

    private var accentBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.63, blue: 0.95).opacity(0.30)
            : Color(red: 0.30, green: 0.38, blue: 0.75).opacity(0.25)
    }
    private var thinkingTextColor: Color { .primary.opacity(0.38) }
    private var headerTextColor: Color { .primary.opacity(0.32) }

    private var isShowingContent: Bool { isExpanded }

    private var previewLine: String {
        let first = text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.count > 80 ? String(first.prefix(80)) + "…" : first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isShowingContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(headerTextColor)
                        .frame(width: 10)
                    Text(isLiveStreaming ? "Thinking…" : "Thought process")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(headerTextColor)
                        .textShimmer(active: isLiveStreaming)
                    if !isShowingContent {
                        Text(previewLine)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isShowingContent ? 6 : 0)

            if isShowingContent {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accentBarColor)
                        .frame(width: 2)
                    Text(text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(thinkingTextColor)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .onChange(of: isLiveStreaming) { _, streaming in
            if streaming { isExpanded = true }
        }
    }
}

// MARK: - Backward compat aliases
typealias MessageBubbleView = MessageRow

// MARK: - Streaming Dots

struct StreamingDots: View {
    let color: Color
    @State private var phase: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.25)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(dot == i ? 1 : 0.3)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation { dot = (dot + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
