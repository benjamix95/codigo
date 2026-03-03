import SwiftUI
import CoderEngine

extension SidePanelView {
    var sourceControlPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if gitPanelStore.isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Source Control", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Git panel is open on the right")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("Open Git panel to view changes")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button {
                        gitPanelStore.isOpen = true
                    } label: {
                        Text("Open Git Panel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            Spacer()
        }
    }
}
