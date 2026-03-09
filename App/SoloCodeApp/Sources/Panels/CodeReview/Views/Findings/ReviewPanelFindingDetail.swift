import CoderEngine
import SwiftUI

/// Detail view for a single finding with description, suggested fix, comments, and actions.
struct ReviewPanelFindingDetail: View {
    @ObservedObject var store: CodeReviewPanelStore
    let finding: CodeReviewFinding
    let onOpenFileAtLocation: (String, Int?) -> Void
    let onBack: () -> Void

    var patch: ReviewPatchArtifact? {
        store.currentPatches.first(where: { $0.findingId == finding.id })
    }

    var patchFailureComment: FindingComment? {
        finding.comments.last(where: {
            $0.author == "system" && $0.content.hasPrefix("Patch preview non disponibile:")
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            Divider().opacity(0.2)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    locationSection
                    summarySection
                    if let verificationSection {
                        verificationSection
                    }
                    if let remediationSection {
                        remediationSection
                    }
                    if let invariantSection {
                        invariantSection
                    }
                    if let patchFailureSection {
                        patchFailureSection
                    }
                    if let patch {
                        patchSection(patch)
                        if let validationSection = validationSection(for: patch) {
                            validationSection
                        }
                    }
                    if !finding.comments.isEmpty {
                        commentsSection
                    }
                    actionsSection
                }
                .padding(12)
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(reviewSeverityColor(finding.severity))
                .frame(width: 3, height: 14)

            Text(finding.severity.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(reviewSeverityColor(finding.severity))

            Spacer()

            Text(finding.id.prefix(8))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("LOCATION")
            Button {
                onOpenFileAtLocation(finding.filePath, finding.lineNumber)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text(finding.filePath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    if let ln = finding.lineNumber {
                        Text(":\(ln)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                        if let eln = finding.endLineNumber {
                            Text("-\(eln)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)
        }
    }
}
