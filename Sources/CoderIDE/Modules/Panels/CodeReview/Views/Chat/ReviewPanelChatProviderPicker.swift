import SwiftUI

struct ReviewPanelChatProviderPicker: View {
    @ObservedObject var store: CodeReviewPanelStore
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.effectivePanelProviderIconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Provider")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    HStack(spacing: 4) {
                        Text(store.effectivePanelProviderLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.92))
                            .lineLimit(1)
                        if store.usesAutomaticProviderSelection {
                            Text("AUTO")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(store.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(store.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(store.accent.opacity(0.16), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            content
                .frame(width: 340)
                .padding(10)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review Provider")
                .font(.system(size: 12, weight: .semibold))

            providerRow(
                id: nil,
                title: "Auto",
                subtitle: store.providerRegistry.selectedProvider?.displayName ?? "Uses current app provider",
                iconName: "wand.and.stars",
                isAuthenticated: true,
                isSelected: store.usesAutomaticProviderSelection
            )

            if !store.panelProviderOptions.isEmpty {
                Divider().opacity(0.15)
            }

            ForEach(store.panelProviderOptions) { option in
                providerRow(
                    id: option.id,
                    title: option.modelName,
                    subtitle: option.displayName,
                    iconName: option.iconName,
                    isAuthenticated: option.isAuthenticated,
                    isSelected: store.selectedProviderOverrideId == option.id
                )
            }
        }
    }

    @ViewBuilder
    private func providerRow(
        id: String?,
        title: String,
        subtitle: String,
        iconName: String,
        isAuthenticated: Bool,
        isSelected: Bool
    ) -> some View {
        Button {
            store.setPanelProviderOverride(id)
            showPopover = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isAuthenticated ? store.accent : .secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isAuthenticated ? .primary : .secondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !isAuthenticated {
                    Text("OFF")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(store.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? store.accent.opacity(0.10) : Color.black.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? store.accent.opacity(0.25) : DesignSystem.Colors.border.opacity(0.16),
                        lineWidth: 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAuthenticated)
    }
}
