import CoderEngine
import SwiftUI

struct ReviewPanelPatchesSection: View {
    let patches: [ReviewPatchArtifact]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("PATCHES")
            if patches.isEmpty {
                Text("Nessuna patch preparata.")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            } else {
                ForEach(patches, id: \.id) { patch in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(patch.findingId)
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text(patch.status.rawValue)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(patch.touchedFiles.joined(separator: ", "))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(String(patch.diffPreview.prefix(220)))
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.75))
                            .lineLimit(5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.25))
                    )
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
    }
}
