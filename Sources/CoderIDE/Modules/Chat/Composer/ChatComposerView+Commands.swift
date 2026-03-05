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

    internal var codeReviewAutofixToggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activeModeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Code Review")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(codeReviewAutofixEnabled
                    ? "Autofix: analysis + parallel fix workers + test loop"
                    : "Discovery: analysis only, no automatic fixes")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle(isOn: $codeReviewAutofixEnabled) {
                Text(codeReviewAutofixEnabled ? "Autofix" : "Discovery")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(codeReviewAutofixEnabled ? DesignSystem.Colors.success : .secondary)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            Text(codeReviewAutofixEnabled ? "Autofix" : "Discovery")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(codeReviewAutofixEnabled ? DesignSystem.Colors.success : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (codeReviewAutofixEnabled ? DesignSystem.Colors.success : activeModeColor)
                        .opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    (codeReviewAutofixEnabled ? DesignSystem.Colors.success : activeModeColor)
                        .opacity(0.25),
                    lineWidth: 0.6
                )
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}
