import CoderEngine
import SwiftUI

/// Root view for the independent Code Review Panel.
/// Receives a `CodeReviewPanelStore` and two closures. No `@Binding`, no `onDispatchAction`.
struct CodeReviewPanelView: View {
    @ObservedObject var store: CodeReviewPanelStore
    let todoStore: TodoStore
    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onOpenFileAtLocation: (String, Int?) -> Void

    private let topInteractiveInset: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            ReviewPanelHeader(store: store, onClose: onClose)

            ReviewPanelSessionBrowser(store: store)

            Divider().opacity(0.3)

            ReviewPanelTabSelector(store: store)

            Divider().opacity(0.2)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.2)

            bottomComposer
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await store.refreshGitContext()
        }
    }

    // MARK: - Tab Content Router

    @ViewBuilder
    private var tabContent: some View {
        switch store.selectedTab {
        case .commands:
            ReviewPanelCommandsTab(store: store, onOpenFile: onOpenFile)
        case .findings:
            ReviewPanelFindingsTab(store: store, onOpenFileAtLocation: onOpenFileAtLocation)
        case .timeline:
            ReviewPanelTimelineTab(store: store)
        case .chat:
            ReviewPanelChatTab(
                store: store,
                todoStore: todoStore,
                onOpenFile: onOpenFile,
                onOpenFileAtLocation: onOpenFileAtLocation
            )
        case .settings:
            ReviewPanelSettingsTab(store: store)
        }
    }

    // MARK: - Bottom Mini Composer

    private var bottomComposer: some View {
        HStack(spacing: 8) {
            if store.isRunning {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Review running...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(store.accent)
                }

                Spacer()

                Button {
                    store.cancelReview()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(DesignSystem.Colors.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        DesignSystem.Colors.error.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            } else if let frozen = store.frozenTimerText {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("Completed in \(frozen)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let sessionId = store.selectedSessionId {
                    Button {
                        store.publishSummaryToChat(sessionId: sessionId)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 8))
                            Text("Export")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(store.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            store.accent.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    Task {
                        await store.startReview(
                            scope: store.scopeTarget,
                            modes: store.selectedModes
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 9))
                        Text("Start Review")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        store.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Host Wrapper (owns the @StateObject)

/// Container that creates and owns the `CodeReviewPanelStore` as `@StateObject`.
/// Use this from the call site where environment objects are available.
struct ReviewPanelHost: View {
    @StateObject private var store: CodeReviewPanelStore
    let todoStore: TodoStore
    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onOpenFileAtLocation: (String, Int?) -> Void

    init(
        taskActivityStore: TaskActivityStore,
        providerRegistry: ProviderRegistry,
        executionController: ExecutionController?,
        workspaceStore: WorkspaceStore,
        openFilesStore: OpenFilesStore,
        todoStore: TodoStore,
        conversationId: UUID?,
        providerFactoryConfigBuilder: @escaping () -> ProviderFactoryConfig,
        onClose: @escaping () -> Void,
        onOpenFile: @escaping (String) -> Void,
        onOpenFileAtLocation: @escaping (String, Int?) -> Void
    ) {
        _store = StateObject(wrappedValue: CodeReviewPanelStore(
            taskActivityStore: taskActivityStore,
            providerRegistry: providerRegistry,
            executionController: executionController,
            workspaceStore: workspaceStore,
            openFilesStore: openFilesStore,
            todoStore: todoStore,
            conversationId: conversationId,
            providerFactoryConfigBuilder: providerFactoryConfigBuilder
        ))
        self.todoStore = todoStore
        self.onClose = onClose
        self.onOpenFile = onOpenFile
        self.onOpenFileAtLocation = onOpenFileAtLocation
    }

    var body: some View {
        CodeReviewPanelView(
            store: store,
            todoStore: todoStore,
            onClose: onClose,
            onOpenFile: onOpenFile,
            onOpenFileAtLocation: onOpenFileAtLocation
        )
        .task {
            await store.consumePendingLaunchRequestIfNeeded()
        }
    }
}
