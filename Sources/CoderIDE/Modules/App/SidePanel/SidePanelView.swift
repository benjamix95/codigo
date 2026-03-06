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
        VStack(spacing: 12) {
            workspaceSummaryCard
            sectionHeaderCard

            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
        .padding(12)
        .frame(maxHeight: .infinity)
    }

    private var workspaceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(activeItem.tint.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: activeItem.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeItem.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(context?.name ?? "No project")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(contextSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                statChip(title: "Section", value: activeItem.shortTitle)
                statChip(title: "Roots", value: "\(context?.folderPaths.count ?? 0)")
                if let activeRootName {
                    statChip(title: "Active", value: activeRootName)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.backgroundPrimary.opacity(0.94),
                            DesignSystem.Colors.backgroundSecondary.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderAccent.opacity(0.65), lineWidth: 0.6)
        )
    }

    private var sectionHeaderCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeItem.tooltip)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(sectionDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: activeItem.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activeItem.tint)
                .padding(8)
                .background(activeItem.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private var contextSubtitle: String {
        guard let context else { return "Apri un progetto per iniziare" }
        if context.folderPaths.count == 1 {
            return context.folderPaths[0]
        }
        return "\(context.folderPaths.count) cartelle attive nel workspace"
    }

    private var activeRootName: String? {
        guard let path = context?.activeFolderPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    private var sectionDescription: String {
        switch activeItem {
        case .explorer:
            return "Naviga file, cartelle e contesto del progetto."
        case .search:
            return "Cerca testo nel workspace e apri i risultati al punto giusto."
        case .sourceControl:
            return "Controlla cambi, stato git e collegamenti al pannello sorgente."
        case .settings:
            return "Preferenze e personalizzazione."
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
