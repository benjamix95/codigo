import SwiftUI

// MARK: - UI Panel Coordinator

/// Centralizes panel visibility, layout flags, and folder-picker state
/// that previously lived as ~22 @State in ContentView.
final class UIPanelCoordinator: ObservableObject {
    /// Altezza usata quando il terminale viene mostrato (pannello “intero” rispetto al default 200).
    static let terminalPreferredOpenHeight: CGFloat = 400

    // MARK: Panel Visibility
    @Published var showTerminal = false
    @Published var terminalHeight: CGFloat = 200
    @Published var showSettings = false
    @Published var showPlanPanel = false
    @Published var showDebugPanel = false
    @Published var showSwarmPanel = false
    @Published var showCodeReviewPanel = false
    @Published var showBrowserPanel = false
    @Published var showChatPanel = true

    // MARK: Navigation
    @Published var selectedConversationId: UUID?
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var activeActivityItem: ActivityBarItem? = .explorer
    @Published var coderMode: CoderMode = .agent
    @Published var preferActiveContextForGlobalThread = true

    // MARK: App Update
    @Published var showAppUpdateAlert = false
    @Published var pendingAppUpdate: AppUpdateCenter.AppUpdateManifest?

    // MARK: Folder Picker
    @Published var isSelectingProjectFolders = false
    @Published var isSelectingAddFolder = false
    @Published var pendingAddFolderContextId: UUID?
    @Published var pendingFolderPickerKind: FolderPickerKind = .none
    @Published var showFolderPicker = false
}
