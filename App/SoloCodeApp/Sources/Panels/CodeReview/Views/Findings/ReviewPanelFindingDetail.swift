import CoderEngine
import SwiftUI

/// Detail view for a single finding with description, suggested fix, comments, and actions.
struct ReviewPanelFindingDetail: View {
    @ObservedObject var store: CodeReviewPanelStore
    let finding: CodeReviewFinding
    let onOpenFileAtLocation: (String, Int?) -> Void
    let onBack: () -> Void
    var chrome: ReviewFindingDetailChrome = .standard

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
            if chrome == .standard {
                detailHeader
                Divider().opacity(0.2)
            } else {
                Divider().opacity(0.12)
            }
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
                        patchPresentation(patch)
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

struct ReviewPipelineJobCard: View {
    let state: ReviewPipelineJobState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !state.phaseLedger.isEmpty {
                phaseTimeline
            }
            metricsRow
            gatesRow
            toolsSection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(state.phaseColor.opacity(0.24), lineWidth: 0.8)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            progressRing
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(state.phaseLabel)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(state.phaseColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(state.phaseColor.opacity(0.12), in: Capsule())
                    Text("Fase \(state.visibleStepNumber) di \(state.visibleStepsTotal)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(summaryText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(state.progressPercent, 100))) / 100.0)
                .stroke(state.phaseColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                if !state.isTerminal && state.toolsRunning > 0 {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                Text(state.progressText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.phaseColor)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metricChip("Tools", value: "\(state.toolsCompleted)/\(state.toolsTotal)")
            metricChip("Candidates", value: "\(state.candidateCount)")
            metricChip("Verified", value: "\(state.verifiedCount)")
            metricChip("Published", value: "\(state.publishedFindingCount)")
            if state.hiddenFindingCount > 0 {
                metricChip("Hidden", value: "\(state.hiddenFindingCount)")
            }
        }
    }

    private var phaseTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.phaseLedger, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.uppercased())
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(entry.status.rawValue.capitalized)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(statusColor(entry.status))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        statusColor(entry.status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
            }
        }
    }

    private var gatesRow: some View {
        HStack(spacing: 8) {
            ForEach(state.gates, id: \.title) { gate in
                HStack(spacing: 5) {
                    Image(systemName: gate.isReady ? "checkmark.seal.fill" : "clock.fill")
                        .font(.system(size: 8))
                    Text(gate.title)
                        .font(.system(size: 8.5, weight: .medium))
                }
                .foregroundStyle(gate.isReady ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    (gate.isReady ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .opacity(0.12),
                    in: Capsule()
                )
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("TOOLS")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                if !state.bundleModes.isEmpty {
                    Text(state.bundleModes.joined(separator: " + "))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }
            }
            ForEach(state.tools) { tool in
                HStack(spacing: 8) {
                    statusDot(tool.status)
                    Text(tool.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    if tool.findingsCount > 0 {
                        Text("\(tool.findingsCount) findings")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metricChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.7)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func statusDot(_ status: ReviewPipelineToolExecution.Status) -> some View {
        Group {
            switch status {
            case .completed:
                Circle().fill(DesignSystem.Colors.success)
            case .running:
                Circle().fill(DesignSystem.Colors.warning)
            case .pending:
                Circle().fill(Color.secondary.opacity(0.35))
            }
        }
        .frame(width: 7, height: 7)
    }

    private func statusColor(_ status: ReviewPipelineLedgerStatus) -> Color {
        switch status {
        case .completed:
            return DesignSystem.Colors.success
        case .running:
            return DesignSystem.Colors.reviewColor
        case .blocked:
            return DesignSystem.Colors.warning
        case .pending:
            return .secondary
        }
    }

    private var summaryText: String {
        if state.publishedFindingCount > 0 {
            return "I risultati mostrati sono verificati e hanno un fix pronto da applicare."
        }
        if state.hiddenFindingCount > 0 {
            return "La revisione sta ancora completando gli ultimi controlli prima di mostrare tutti i risultati."
        }
        if state.isTerminal {
            return "La revisione si è conclusa senza risultati pubblicabili."
        }
        return "La revisione è in corso e aggiornerà i risultati man mano che diventano affidabili."
    }
}
