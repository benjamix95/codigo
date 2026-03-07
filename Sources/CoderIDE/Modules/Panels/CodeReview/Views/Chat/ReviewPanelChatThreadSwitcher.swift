import SwiftUI

struct ReviewPanelChatThreadSwitcher: View {
    @ObservedObject var store: CodeReviewPanelStore
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 9, weight: .semibold))
                if let active = activeThread {
                    Text(active.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                    Text(active.subtitle)
                        .font(.system(size: 8.5))
                        .foregroundStyle(active.isProcessing ? store.accent : .secondary)
                        .lineLimit(1)
                } else {
                    Text("Chats")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                if visibleThreadsCount > 0 {
                    Text("\(visibleThreadsCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(store.accent.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(store.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(store.accent.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            content
                .frame(width: 360, height: 360)
                .padding(10)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Panel Chats")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    store.createNewChatThread()
                    showPopover = false
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(store.accent)
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    threadSection(
                        title: "Active",
                        threads: store.chatThreads.filter { !$0.archived }
                    )
                    threadSection(
                        title: "Archived",
                        threads: store.chatThreads.filter(\.archived)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func threadSection(
        title: String,
        threads: [ReviewPanelChatThreadState]
    ) -> some View {
        if !threads.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                ForEach(threads) { thread in
                    threadRow(thread)
                }
            }
        }
    }

    private func threadRow(_ thread: ReviewPanelChatThreadState) -> some View {
        let isSelected = store.activeChatThreadId == thread.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? store.accent : .primary)
                        .lineLimit(1)
                    if thread.isProcessing {
                        Text("LIVE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(store.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(store.accent.opacity(0.12), in: Capsule())
                    }
                }
                Text(thread.subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                if thread.archived {
                    store.restoreChatThread(thread.id)
                } else {
                    store.archiveChatThread(thread.id)
                }
            } label: {
                Image(systemName: thread.archived ? "tray.and.arrow.up" : "archivebox")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)

            Button {
                store.deleteChatThread(thread.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)

            Button {
                store.selectChatThread(thread.id)
                showPopover = false
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? store.accent : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? store.accent.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected ? store.accent.opacity(0.22) : DesignSystem.Colors.border.opacity(0.15),
                    lineWidth: 0.5
                )
        )
    }

    private var activeThread: ReviewPanelChatThreadState? {
        guard let activeChatThreadId = store.activeChatThreadId else { return nil }
        return store.chatThreads.first(where: { $0.id == activeChatThreadId })
    }

    private var visibleThreadsCount: Int {
        store.chatThreads.filter { !$0.archived }.count
    }
}
