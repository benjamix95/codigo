import SwiftUI
import CoderEngine

struct SidebarView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore

    @Binding var selectedConversationId: UUID?
    @Binding var showSettings: Bool
    @Binding var isSelectingProjectFolders: Bool
    let preferActiveContextForGlobalThread: Bool

    @State var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    quickActions
                    searchField
                    contextsSection
                    threadsSection
                }
                .padding(14)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sidebar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(activeContext?.name ?? "Global")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                createThread(contextId: activeContext?.id)
            } label: {
                label("New Thread", icon: "plus.bubble")
            }
            .buttonStyle(.plain)

            Button {
                isSelectingProjectFolders = true
            } label: {
                label("Open Project", icon: "folder.badge.plus")
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        TextField("Search threads", text: $query)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
    }

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Contexts")

            if orderedContexts.isEmpty {
                emptyState("No context available")
            } else {
                ForEach(orderedContexts) { context in
                    Button {
                        attachConversation(to: context.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: context.id == activeContext?.id ? "folder.fill" : "folder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(context.id == activeContext?.id ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(context.id == activeContext?.id ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(activeContext == nil ? "Global Threads" : "Threads")

            if visibleThreads.isEmpty {
                emptyState(activeContext == nil ? "No global threads" : "No threads in this context")
            } else {
                ForEach(visibleThreads) { conversation in
                    Button {
                        selectConversation(conversation)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: conversation))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(color(for: conversation))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title)
                                    .font(.system(size: 11.5, weight: conversation.id == selectedConversationId ? .semibold : .medium))
                                    .foregroundStyle(conversation.id == selectedConversationId ? Color.accentColor : .primary)
                                    .lineLimit(1)
                                Text(threadSubtitle(conversation))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(conversation.id == selectedConversationId ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.02))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(providerRegistry.selectedProviderId ?? "No provider")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }
}
