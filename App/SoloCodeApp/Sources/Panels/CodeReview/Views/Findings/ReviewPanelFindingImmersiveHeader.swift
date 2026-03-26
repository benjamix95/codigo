import CoderEngine
import SwiftUI

struct ReviewPanelFindingImmersiveHeader: View {
    @ObservedObject var store: CodeReviewPanelStore
    let finding: CodeReviewFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    store.leaveImmersiveFindingWorkspace()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Findings")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(store.accent)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text(domainBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(domainColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(domainColor.opacity(0.12), in: Capsule())

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(reviewSeverityColor(finding.severity))
                    .frame(width: 3, height: 14)
                Text(finding.severity.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(reviewSeverityColor(finding.severity))
            }

            Text(finding.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var domainBadge: String {
        finding.reviewImmersiveDomainIsSecurity ? "SECURITY" : "BUG"
    }

    private var domainColor: Color {
        finding.reviewImmersiveDomainIsSecurity
            ? DesignSystem.Colors.warning
            : DesignSystem.Colors.reviewColor
    }
}
