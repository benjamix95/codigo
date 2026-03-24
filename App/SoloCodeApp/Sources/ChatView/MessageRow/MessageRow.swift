import AppKit
import CoderEngine
import QuickLookUI
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
    var streamingReasoningBlocks: [ReasoningBlock] = []
    var showStreamingBar: Bool = true
    let onFileClicked: (String) -> Void
    var onRestoreCheckpoint: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var canRewind: Bool = false
    var hasCheckpointForRestore: Bool = false
    var showTopDivider: Bool = false
    @State var isHovered = false
    @State var isActionsHovered = false
    @State var didCopyMessage = false
    @State var hoverTask: Task<Void, Never>?
    @State var isEditingInline = false
    @State var editText = ""
    let userRowMaxWidth: CGFloat = 640
    let assistantRowMaxWidth: CGFloat = 860
    let userImageThumbWidth: CGFloat = 140
    let userImageThumbHeight: CGFloat = 100

    var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    var shouldShowStreamingBar: Bool {
        showStreamingBar && isActivelyStreaming
    }

    var isUser: Bool { message.role == .user }
    var rowMaxWidth: CGFloat { isUser ? userRowMaxWidth : assistantRowMaxWidth }
    var contentMaxWidth: CGFloat { isUser ? 580 : 800 }
    var shouldShowCopyAction: Bool { Self.shouldShowCopyAction(for: message) }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            if showTopDivider {
                messageDivider()
            }
            if isUser {
                userHeader()
            } else {
                assistantHeader()
            }
            HStack(alignment: .top, spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                messageContent()
                if !isUser { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: rowMaxWidth, alignment: isUser ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                isHovered = true
            } else {
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    guard !Task.isCancelled else { return }
                    if !isActionsHovered {
                        isHovered = false
                    }
                }
            }
        }
        .onDisappear {
            hoverTask?.cancel()
            hoverTask = nil
        }
    }
}
