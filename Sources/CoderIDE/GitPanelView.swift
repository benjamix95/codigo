import SwiftUI
import CoderEngine

struct GitPanelView: View {
    @ObservedObject var store: GitPanelStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    let effectiveContext: EffectiveContext
    let onOpenFile: (String) -> Void

    @State private var expandedSection: GitPanelSection = .changedFiles
    @State private var showCommitForm = false

    enum GitPanelSection: String, CaseIterable {
        case changedFiles = "Changed Files"
        case commitHistory = "History"
        case branches = "Branches"
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.4)
            segmentPicker
            Divider().opacity(0.4)
            panelContent
            Divider().opacity(0.4)
            commitSection
        }
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
        .background(DesignSystem.Colors.backgroundPrimary)
        .sidebarPanel(cornerRadius: 14)
        .onAppear {
            store.refresh(workingDirectory: effectiveContext.primaryPath)
        }
    }

    // MARK: - Header
    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.agentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentBranch)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if let status = store.status {
                    HStack(spacing: 6) {
                        Text("\(status.changedFiles) files")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("+\(status.added + status.untracked)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(status.removed)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                }
            }
            Spacer()
            Button {
                store.refresh(workingDirectory: effectiveContext.primaryPath)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.isOpen = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Chiudi pannello Git")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Segment Picker
    private var segmentPicker: some View {
        HStack(spacing: 2) {
            ForEach(GitPanelSection.allCases, id: \.self) { section in
                let isSelected = expandedSection == section
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        expandedSection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: sectionIcon(section))
                            .font(.system(size: 9.5))
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        if section == .changedFiles && !store.changedFiles.isEmpty {
                            Text("\(store.changedFiles.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    isSelected ? DesignSystem.Colors.agentColor.opacity(0.2) : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(isSelected ? DesignSystem.Colors.agentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? DesignSystem.Colors.agentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func sectionIcon(_ section: GitPanelSection) -> String {
        switch section {
        case .changedFiles: return "doc.badge.gearshape"
        case .commitHistory: return "clock.arrow.circlepath"
        case .branches: return "arrow.triangle.branch"
        }
    }

    // MARK: - Panel Content
    @ViewBuilder
    private var panelContent: some View {
        switch expandedSection {
        case .changedFiles:
            changedFilesSection
        case .commitHistory:
            commitHistorySection
        case .branches:
            branchesSection
        }
    }

    // MARK: - Changed Files
    private var changedFilesSection: some View {
        VStack(spacing: 0) {
            if store.changedFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.5))
                    Text("Nessun file modificato")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                // Summary bar
                HStack(spacing: 8) {
                    Text("\(store.changedFiles.count) files")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("+\(store.totalAdded)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("-\(store.totalRemoved)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.error)
                    Spacer()
                    Button {
                        store.undoAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                            Text("Undo All")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.error.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().opacity(0.3).padding(.horizontal, 14)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.changedFiles) { file in
                            fileRow(file)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ file: GitChangedFile) -> some View {
        HStack(spacing: 8) {
            // Status badge
            Text(file.status)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor(file.status))
                .frame(width: 18, height: 18)
                .background(statusColor(file.status).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            // File name
            Button {
                onOpenFile(file.path)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text((file.path as NSString).lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    let dir = (file.path as NSString).deletingLastPathComponent
                    if !dir.isEmpty {
                        Text(dir)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Diff stats
            HStack(spacing: 3) {
                Text("+\(file.added)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(file.removed)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            // Undo button
            Button {
                store.undo(path: file.path)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Ripristina file")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.clear)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A", "??": return DesignSystem.Colors.success
        case "D": return DesignSystem.Colors.error
        case "M": return DesignSystem.Colors.warning
        case "R": return DesignSystem.Colors.info
        default: return .secondary
        }
    }

    // MARK: - Commit History
    private var commitHistorySection: some View {
        VStack(spacing: 0) {
            if store.commitLog.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Nessun commit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.commitLog) { entry in
                            commitRow(entry)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitRow(_ entry: GitLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Commit dot / timeline
            VStack(spacing: 0) {
                Circle()
                    .fill(DesignSystem.Colors.agentColor.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subject)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(entry.shortSha)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.agentColor.opacity(0.7))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.authorName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    // MARK: - Branches
    private var branchesSection: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Cerca branch...", text: $store.branchSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if store.filteredBranches.isEmpty {
                Text("Nessun branch trovato")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredBranches) { branch in
                            branchRow(branch)
                        }
                    }
                }
            }

            Divider().opacity(0.3).padding(.horizontal, 14)

            // Create new branch
            Button {
                store.newBranchName = store.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                store.showCreateBranch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.agentColor)
                    Text("Crea nuovo branch")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(store.gitRoot == nil || store.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $store.showCreateBranch) {
            createBranchSheet
        }
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        Button {
            store.switchBranch(branch.name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(branch.isCurrent ? DesignSystem.Colors.agentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch.name)
                        .font(.system(size: 12, weight: branch.isCurrent ? .bold : .medium))
                        .foregroundStyle(.primary)
                    if branch.isCurrent, let st = store.status, st.changedFiles > 0 {
                        HStack(spacing: 4) {
                            Text("\(st.changedFiles) uncommitted")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if branch.isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.agentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy || branch.isCurrent)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private var createBranchSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Crea e checkout nuovo branch")
                .font(.system(size: 15, weight: .semibold))
            TextField("Nome branch", text: $store.newBranchName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annulla") {
                    store.showCreateBranch = false
                }
                Button("Crea") {
                    store.createAndCheckoutBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    store.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isBusy)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    // MARK: - Commit Section (bottom)
    private var commitSection: some View {
        VStack(spacing: 10) {
            // Commit message
            HStack(spacing: 8) {
                TextField("Messaggio commit (auto se vuoto)", text: $store.commitMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...3)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.6)
                    )
            }

            HStack(spacing: 8) {
                // Include unstaged toggle
                Toggle(isOn: $store.includeUnstaged) {
                    Text("Unstaged")
                        .font(.system(size: 10, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                // Push button
                Button {
                    store.pushOnly()
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.canPush ? DesignSystem.Colors.info : DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!store.canPush || store.isBusy)
                .help("Push")

                // Commit button
                Button {
                    store.runCommitFlow(providerRegistry: providerRegistry)
                } label: {
                    HStack(spacing: 5) {
                        if store.isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Commit")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        DesignSystem.Colors.agentColor,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy || (store.status?.changedFiles ?? 0) == 0)
            }

            // Status messages
            if let success = store.successMessage, !success.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text(success)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.success)
                        .lineLimit(1)
                }
            }
            if let err = store.error, !err.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignSystem.Colors.error)
                    Text(err)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.error)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
