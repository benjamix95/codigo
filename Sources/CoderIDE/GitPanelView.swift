import SwiftUI
import CoderEngine

struct GitPanelView: View {
    @ObservedObject var store: GitPanelStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    let effectiveContext: EffectiveContext
    let onOpenFile: (String) -> Void

    @State private var expandedSection: GitPanelSection = .changedFiles

    enum GitPanelSection: String, CaseIterable {
        case changedFiles = "Changes"
        case commitHistory = "History"
        case branches = "Branches"
        case stash = "Stash"
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.4)
            actionBar
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
        .alert("Delete branch?", isPresented: $store.showDeleteBranchConfirm) {
            Button("Cancel", role: .cancel) {
                store.branchToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let name = store.branchToDelete {
                    store.deleteBranch(name: name, force: false)
                }
            }
            Button("Force Delete", role: .destructive) {
                if let name = store.branchToDelete {
                    store.deleteBranch(name: name, force: true)
                }
            }
        } message: {
            Text("Delete branch \"\(store.branchToDelete ?? "")\"?")
        }
    }

    // MARK: - Header
    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.agentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.currentBranch)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    if store.aheadCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(store.aheadCount)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(DesignSystem.Colors.info)
                    }
                    if store.behindCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(store.behindCount)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }
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
            .help("Close Git panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Action Bar
    private var actionBar: some View {
        HStack(spacing: 4) {
            actionButton(icon: "arrow.down.circle", label: "Fetch", disabled: store.isBusy) {
                store.fetch()
            }
            actionButton(icon: "arrow.down.to.line", label: "Pull", disabled: store.isBusy) {
                store.pull()
            }
            actionButton(icon: "arrow.up.to.line", label: "Push", disabled: store.isBusy || !store.canPush) {
                store.pushOnly()
            }
            Spacer()
            actionButton(icon: "tray.and.arrow.down", label: "Stash", disabled: store.isBusy || (store.status?.changedFiles ?? 0) == 0) {
                store.stash(message: store.stashMessage.isEmpty ? nil : store.stashMessage)
            }
            if !store.stashEntries.isEmpty {
                actionButton(icon: "tray.and.arrow.up", label: "Pop", disabled: store.isBusy) {
                    store.stashPop()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func actionButton(icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(disabled ? .tertiary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
                    HStack(spacing: 4) {
                        Image(systemName: sectionIcon(section))
                            .font(.system(size: 9))
                        Text(section.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                        if let badge = sectionBadge(section) {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    isSelected ? DesignSystem.Colors.agentColor.opacity(0.2) : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                    }
                    .foregroundStyle(isSelected ? DesignSystem.Colors.agentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? DesignSystem.Colors.agentColor.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func sectionIcon(_ section: GitPanelSection) -> String {
        switch section {
        case .changedFiles: return "doc.badge.gearshape"
        case .commitHistory: return "clock.arrow.circlepath"
        case .branches: return "arrow.triangle.branch"
        case .stash: return "tray.2"
        }
    }

    private func sectionBadge(_ section: GitPanelSection) -> String? {
        switch section {
        case .changedFiles:
            let count = store.changedFiles.count
            return count > 0 ? "\(count)" : nil
        case .stash:
            let count = store.stashEntries.count
            return count > 0 ? "\(count)" : nil
        default:
            return nil
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
        case .stash:
            stashSection
        }
    }

    // MARK: - Changed Files (Staged / Unstaged split)
    private var changedFilesSection: some View {
        VStack(spacing: 0) {
            if store.changedFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.5))
                    Text("No changed files")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Staged section
                        if !store.stagedFiles.isEmpty {
                            fileSectionHeader(
                                title: "Staged Changes",
                                count: store.stagedFiles.count,
                                color: DesignSystem.Colors.success,
                                action: { store.unstageAll() },
                                actionLabel: "Unstage All",
                                actionIcon: "minus.circle"
                            )
                            ForEach(store.stagedFiles) { file in
                                fileRow(file, staged: true)
                            }
                        }

                        // Unstaged section
                        fileSectionHeader(
                            title: "Changes",
                            count: store.unstagedFiles.count,
                            color: .secondary,
                            action: { store.stageAll() },
                            actionLabel: "Stage All",
                            actionIcon: "plus.circle"
                        )
                        ForEach(store.unstagedFiles) { file in
                            fileRow(file, staged: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileSectionHeader(
        title: String,
        count: Int,
        color: Color,
        action: @escaping () -> Void,
        actionLabel: String,
        actionIcon: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
            Spacer()
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 9, weight: .bold))
                    Text(actionLabel)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    private func fileRow(_ file: GitChangedFile, staged: Bool) -> some View {
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

            // Stage / Unstage button
            if staged {
                Button { store.unstageFile(path: file.path) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.plain)
                .help("Unstage")
            } else {
                Button { store.stageFile(path: file.path) } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
                .buttonStyle(.plain)
                .help("Stage")

                // Undo button (only for unstaged)
                Button { store.undo(path: file.path) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Discard changes")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
                    Text("No commits")
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
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.authorName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
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
    @State private var branchSegment: BranchSegment = .local
    enum BranchSegment: String, CaseIterable { case local = "Local", remote = "Remote" }

    private var branchesSection: some View {
        VStack(spacing: 0) {
            // Search + segment
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Search branches...", text: $store.branchSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Local/Remote picker
            Picker("", selection: $branchSegment) {
                ForEach(BranchSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            if branchSegment == .local {
                localBranchesContent
            } else {
                remoteBranchesContent
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
                    Text("New branch")
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

    private var localBranchesContent: some View {
        Group {
            if store.filteredBranches.isEmpty {
                Text("No branches found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredBranches) { branch in
                            localBranchRow(branch)
                        }
                    }
                }
            }
        }
    }

    private func localBranchRow(_ branch: GitBranch) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(branch.isCurrent ? DesignSystem.Colors.agentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(.system(size: 12, weight: branch.isCurrent ? .bold : .medium))
                    .foregroundStyle(.primary)
                if branch.isCurrent, let st = store.status, st.changedFiles > 0 {
                    Text("\(st.changedFiles) uncommitted")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if branch.isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.agentColor)
            } else {
                // Delete button
                Button {
                    store.branchToDelete = branch.name
                    store.showDeleteBranchConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.error.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete branch")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !branch.isCurrent && !store.isBusy {
                store.switchBranch(branch.name)
            }
        }
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private var remoteBranchesContent: some View {
        Group {
            let query = store.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let filtered = query.isEmpty ? store.remoteBranches : store.remoteBranches.filter { $0.name.lowercased().contains(query) }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No remote branches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if store.remoteBranches.isEmpty {
                        Button("Fetch remotes") { store.fetch() }
                            .font(.system(size: 11, weight: .semibold))
                            .disabled(store.isBusy)
                    }
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { branch in
                            remoteBranchRow(branch)
                        }
                    }
                }
            }
        }
    }

    private func remoteBranchRow(_ branch: GitBranch) -> some View {
        Button {
            store.checkoutRemoteBranch(name: branch.name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(branch.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private var createBranchSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create & checkout new branch")
                .font(.system(size: 15, weight: .semibold))
            TextField("Branch name", text: $store.newBranchName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    store.showCreateBranch = false
                }
                Button("Create") {
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

    // MARK: - Stash Section
    private var stashSection: some View {
        VStack(spacing: 0) {
            if store.stashEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No stash entries")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.stashEntries) { entry in
                            stashEntryRow(entry)
                        }
                    }
                }
            }

            Divider().opacity(0.3).padding(.horizontal, 14)

            // Stash input
            HStack(spacing: 8) {
                TextField("Stash message (optional)", text: $store.stashMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                Button {
                    store.stash(message: store.stashMessage.isEmpty ? nil : store.stashMessage)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Stash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.agentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy || (store.status?.changedFiles ?? 0) == 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stashEntryRow(_ entry: GitStashEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("stash@{\(entry.index)}")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.agentColor.opacity(0.7))
                Text(entry.message)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
            }
            Spacer()
            // Pop
            Button { store.stashPop() } label: {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.success)
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
            .help("Pop stash")
            // Drop
            Button { store.stashDrop(index: entry.index) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
            .help("Drop stash")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    // MARK: - Commit Section (bottom)
    private var commitSection: some View {
        VStack(spacing: 8) {
            // Commit message
            TextField("Commit message (auto if empty)", text: $store.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.6)
                )

            HStack(spacing: 6) {
                // Stage All & Commit shortcut
                if !store.unstagedFiles.isEmpty && store.stagedFiles.isEmpty {
                    Button {
                        store.stageAll()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 9, weight: .bold))
                            Text("Stage All")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

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
                    .background(DesignSystem.Colors.agentColor, in: Capsule())
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
