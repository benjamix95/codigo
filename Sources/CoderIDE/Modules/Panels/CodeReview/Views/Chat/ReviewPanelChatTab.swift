import CoderEngine
import SwiftUI

/// Independent chat tab for the Code Review Panel.
/// All messages stay within the panel; nothing goes to the main chat.
struct ReviewPanelChatTab: View {
    @ObservedObject var store: CodeReviewPanelStore
    let onOpenFile: (String) -> Void
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.chatMessages.isEmpty {
                emptyState
            } else {
                messageList
            }
            Divider().opacity(0.2)
            ReviewPanelChatComposer(
                store: store,
                inputText: $inputText,
                onSend: sendMessage,
                onCancel: { store.cancelChatStream() }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("Review Chat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Ask anything about the current review,\nfindings, or code quality.")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)

            presetChips
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Preset Chips

    private var presetChips: some View {
        VStack(spacing: 4) {
            ForEach(ReviewChatPreset.defaults) { preset in
                Button {
                    Task { await store.sendPresetMessage(preset) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 9))
                        Text(preset.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        store.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    ForEach(store.chatMessages) { msg in
                        ReviewPanelChatBubble(
                            message: msg,
                            accent: store.accent,
                            onOpenFile: onOpenFile,
                            onSelectFinding: { store.focusFinding($0) }
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: store.chatMessages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: store.chatMessages.last?.content) {
                scrollToBottom(proxy)
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task { await store.sendChatMessage(text) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = store.chatMessages.last?.id {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}
