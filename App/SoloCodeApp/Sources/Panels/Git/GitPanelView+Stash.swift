import SwiftUI

extension GitPanelView {
    // MARK: - Stash Section

    var stashSection: some View {
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

            Divider().opacity(0.3).padding(.horizontal, 8)

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
            .padding(.horizontal, 8)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .hoverHighlight(Color.primary.opacity(0.04))
    }
}

