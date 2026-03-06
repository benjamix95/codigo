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
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: activeItem.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(activeItem.tint)
                    .frame(width: 28, height: 28)
                    .background(activeItem.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeItem.tooltip)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(context?.name ?? "No project")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if let activeRoot = context?.activeFolderPath {
                Text(activeRoot)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.82))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }
}
