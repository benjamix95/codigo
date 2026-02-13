import SwiftUI

/// Mostra le opzioni del piano con possibilità di selezione o risposta custom
struct PlanOptionsView: View {
    let options: [PlanOption]
    let onSelectOption: (PlanOption) -> Void
    let onCustomResponse: (String) -> Void
    let planColor: Color

    @State private var customText = ""
    @FocusState private var isCustomFocused: Bool

    init(
        options: [PlanOption],
        planColor: Color = DesignSystem.Colors.info,
        onSelectOption: @escaping (PlanOption) -> Void,
        onCustomResponse: @escaping (String) -> Void
    ) {
        self.options = options
        self.planColor = planColor
        self.onSelectOption = onSelectOption
        self.onCustomResponse = onCustomResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Scegli un'opzione o aggiungi una risposta")
                .font(DesignSystem.Typography.subheadlineMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            ForEach(options) { opt in
                Button {
                    onSelectOption(opt)
                } label: {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Text("\(opt.id)")
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(planColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.title)
                                .font(DesignSystem.Typography.subheadlineMedium)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .lineLimit(2)
                            if opt.fullText != opt.title, opt.fullText.count > opt.title.count + 20 {
                                Text(opt.fullText)
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right.circle")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(planColor.opacity(0.8))
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .stroke(planColor.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
                .hoverEffect(scale: 1.01)
            }

            Divider()
                .background(DesignSystem.Colors.divider)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Altra risposta")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
                    TextField("Scrivi la tua risposta...", text: $customText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1...4)
                        .focused($isCustomFocused)
                        .padding(DesignSystem.Spacing.sm)
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .fill(.ultraThinMaterial)
                                .opacity(0.6)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(planColor.opacity(0.5), lineWidth: 0.5)
                        }

                    Button {
                        let t = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty {
                            onCustomResponse(t)
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(customText.isEmpty ? DesignSystem.Colors.textTertiary : planColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(customText.isEmpty)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(Color.white.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(planColor.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}
