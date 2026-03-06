import SwiftUI
import CoderEngine

extension SidePanelView {
    var sourceControlPanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if gitPanelStore.isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Source Control pronto", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Il pannello Git è già disponibile. Usa questa sezione come hub veloce.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.7))
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(DesignSystem.Colors.reviewColor)
                    Text("Apri il pannello Git")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Qui vedrai un accesso rapido a branch, stato file e azioni principali.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        gitPanelStore.isOpen = true
                    } label: {
                        Text("Apri Git Panel")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DesignSystem.Colors.reviewColor.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            Spacer()
        }
        .padding(10)
    }
}
