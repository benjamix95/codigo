import SwiftUI
import CoderEngine

struct SidePanelView: View {
    struct ExplorerEntry: Hashable {
        let name: String
        let fullPath: String
        let isDirectory: Bool
    }

    let activeItem: ActivityBarItem
    let context: ProjectContext?
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var gitPanelStore: GitPanelStore

    @State var expandedFolders: Set<String> = []
    @State var searchQuery = ""
    @State var searchResults: [(path: String, line: Int, text: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.3)

            switch activeItem {
            case .explorer:
                explorerPanelContent
            case .search:
                searchPanelContent
            case .sourceControl:
                sourceControlPanelContent
            case .settings:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundPrimary)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DesignSystem.Colors.border).frame(width: 0.5)
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Text(activeItem.tooltip.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
