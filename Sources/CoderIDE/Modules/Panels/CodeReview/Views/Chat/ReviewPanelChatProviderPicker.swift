import SwiftUI

struct ReviewPanelChatProviderPicker: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        Menu {
            Button {
                store.setPanelProviderOverride(nil)
            } label: {
                Label("Auto", systemImage: "wand.and.stars")
            }

            Divider()

            ForEach(store.panelProviderOptions) { option in
                Button {
                    store.setPanelProviderOverride(option.id)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.modelName)
                            Text(option.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: option.iconName)
                    }
                }
                .disabled(!option.isAuthenticated)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.effectivePanelProviderIconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if store.usesAutomaticProviderSelection {
                            Text("Auto")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(store.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(store.accent.opacity(0.12), in: Capsule())
                        }
                        Text(store.effectivePanelProviderLabel)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(1)
                    }
                    Text(store.effectivePanelProviderName)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.2), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
