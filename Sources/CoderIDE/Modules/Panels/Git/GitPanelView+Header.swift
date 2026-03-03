import SwiftUI

extension GitPanelView {
    // MARK: - Header

    var panelHeader: some View {
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
                store.isOpen = false
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
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - Action Bar

    var actionBar: some View {
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
        .padding(.horizontal, 6)
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

    var segmentPicker: some View {
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

    func sectionBadge(_ section: GitPanelSection) -> String? {
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
    var panelContent: some View {
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
}
