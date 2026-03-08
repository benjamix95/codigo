import CoderEngine
import SwiftUI

struct ReviewPanelCandidatesSection: View {
    let candidates: [ReviewCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("CANDIDATES")
            if candidates.isEmpty {
                Text("Nessun candidate non verificato.")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            } else {
                ForEach(candidates, id: \.id) { candidate in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(candidate.verificationStatus == .verified ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.filePath)
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            Text(candidate.message)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(candidate.verificationStatus.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.quaternary)
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
