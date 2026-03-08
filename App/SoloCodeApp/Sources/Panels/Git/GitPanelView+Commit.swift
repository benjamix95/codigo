import SwiftUI

extension GitPanelView {
    // MARK: - Commit Section (bottom)

    var commitSection: some View {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

