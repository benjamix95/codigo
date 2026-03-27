import SwiftUI

extension ChatComposerView {
    internal var allSlashCommandPresets: [QuickCommandPreset] {
        let combined = quickCommandPresets + slashCommandPresets
        var seen: Set<String> = []
        return combined.filter { preset in
            seen.insert(preset.id).inserted
        }
    }

    internal var quickCommandsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(quickCommandPresets) { preset in
                    HStack(spacing: 5) {
                        Button {
                            onApplyQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if let icon = preset.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 8))
                                        .foregroundStyle(activeModeColor)
                                }
                                Text(preset.slash)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(activeModeColor)
                                Text(preset.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Color(nsColor: .controlBackgroundColor).opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(activeModeColor.opacity(0.22), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRunQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(activeModeColor, in: Circle())
                        }
                    }
                    .help(preset.prompt)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    internal var reviewModeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(reviewModePresets) { preset in
                    Button {
                        onToggleReviewMode(preset.id)
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = preset.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 9))
                            }
                            Text(preset.label)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(
                            preset.isSelected ? activeModeColor : .secondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    preset.isSelected
                                        ? activeModeColor.opacity(0.14)
                                        : Color(nsColor: .controlBackgroundColor).opacity(0.38)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    preset.isSelected
                                        ? activeModeColor.opacity(0.28)
                                        : DesignSystem.Colors.border.opacity(0.14),
                                    lineWidth: 0.6
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    internal var slashMatches: [QuickCommandPreset] {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        guard !trimmed.contains("\n") else { return [] }
        let query = trimmed.lowercased()
        return allSlashCommandPresets.filter {
            $0.slash.lowercased().contains(query) || $0.label.lowercased().contains(query)
        }
        .prefix(6)
        .map { $0 }
    }

    internal var slashAutocompletePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Quick commands")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(slashMatches) { preset in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.slash)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(activeModeColor)
                        Text(preset.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Insert") {
                        onApplyQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    Button("Run now") {
                        onRunQuickCommand("\(preset.slash)\n\n\(preset.prompt)")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.55), lineWidth: 0.6)
        )
    }

    internal var providerNotReadyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(providerNotReadyMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, isIDEStyle ? 12 : 16)
        .padding(.vertical, isIDEStyle ? 6 : 8)
        .background(Color.orange.opacity(0.08))
    }

    internal var noProjectOpenBanner: some View {
        VStack(spacing: isIDEStyle ? 10 : 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: isIDEStyle ? 38 : 42, height: isIDEStyle ? 38 : 42)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: isIDEStyle ? 15 : 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }

            VStack(spacing: 4) {
                Text("Apri un progetto per iniziare")
                    .font(.system(size: isIDEStyle ? 13 : 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text("Aggiungi una cartella o un workspace dalla barra laterale per creare thread e inviare messaggi.")
                    .font(.system(size: isIDEStyle ? 11.5 : 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isIDEStyle ? 18 : 24)
        .padding(.vertical, isIDEStyle ? 16 : 18)
        .background(
            RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.025),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .padding(.horizontal, isIDEStyle ? 8 : 12)
        .padding(.bottom, isIDEStyle ? 4 : 6)
    }
}
