import SwiftUI

// MARK: - Debug Pipeline Status Card

extension DebugPanelView {

    @ViewBuilder
    var debugPipelineStatusCard: some View {
        if debugStore.phase != .idle {
            VStack(alignment: .leading, spacing: 12) {
                pipelineHeader
                pipelinePhaseTimeline
                pipelineMetricsRow
                pipelineGatesRow
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(0.24), lineWidth: 0.8)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

// MARK: - Header

extension DebugPanelView {

    var pipelineHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            pipelineProgressRing
            VStack(alignment: .leading, spacing: 4) {
                Text(pipelineTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(debugStore.phase.label)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(pipelineCurrentPhaseColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            pipelineCurrentPhaseColor.opacity(0.12),
                            in: Capsule()
                        )
                    Text("Fase \(pipelineStepNumber) di \(pipelineTotalSteps)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(pipelineSummaryText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    var pipelineProgressRing: some View {
        let progress = CGFloat(pipelineProgressPercent) / 100.0
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    pipelineCurrentPhaseColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                if debugStore.phase.isActive {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                Text("\(pipelineProgressPercent)%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(pipelineCurrentPhaseColor)
            }
        }
        .frame(width: 52, height: 52)
    }
}

// MARK: - Phase Timeline

extension DebugPanelView {

    var pipelinePhaseTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DebugFlowPhase.mainPhases, id: \.self) { phase in
                    let status = pipelinePhaseStatus(phase)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.label.uppercased())
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(status.capitalized)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(pipelineStatusColor(status))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        pipelineStatusColor(status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
            }
        }
    }

    func pipelinePhaseStatus(_ phase: DebugFlowPhase) -> String {
        let currentIdx = debugStore.phase.mainPhase.phaseIndex
        let phaseIdx = phase.phaseIndex
        if phaseIdx < currentIdx { return "completed" }
        if phaseIdx == currentIdx { return "running" }
        return "pending"
    }

    func pipelineStatusColor(_ status: String) -> Color {
        switch status {
        case "completed": return DesignSystem.Colors.success
        case "running":   return accent
        case "blocked":   return DesignSystem.Colors.warning
        default:          return .secondary
        }
    }
}
