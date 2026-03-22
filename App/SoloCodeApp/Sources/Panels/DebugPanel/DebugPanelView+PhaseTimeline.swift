import SwiftUI
import CoderEngine

extension DebugPanelView {
    // MARK: - Phase Timeline

    var primaryPhases: [DebugFlowPhase] {
        [.describing, .reproducing, .fixing, .verifying, .resolved]
    }

    var currentPrimaryPhase: DebugFlowPhase {
        debugStore.phase == .instrumenting ? .fixing : debugStore.phase
    }

    var currentPrimaryIndex: Int {
        primaryPhases.firstIndex(of: currentPrimaryPhase) ?? 0
    }

    var phaseTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(primaryPhases.enumerated()), id: \.offset) { index, phase in
                    let isCompleted = index < currentPrimaryIndex || currentPrimaryPhase == .resolved
                    let isCurrent = index == currentPrimaryIndex && currentPrimaryPhase != .resolved
                    let isFuture = index > currentPrimaryIndex && currentPrimaryPhase != .resolved

                    phaseNode(phase, isCompleted: isCompleted, isCurrent: isCurrent, isFuture: isFuture)

                    if index < primaryPhases.count - 1 {
                        phaseConnector(isCompleted: isCompleted && !isCurrent)
                    }
                }
            }
            .padding(.horizontal, 4)

            if shouldShowFixSubpipeline {
                fixSubPipeline
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !phaseDetailLabel.isEmpty {
                HStack(spacing: 6) {
                    if debugStore.phase.isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(accent.opacity(0.6))
                    }
                    Text(phaseDetailLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            currentPrimaryPhase == .resolved
                            ? DesignSystem.Colors.success
                            : DesignSystem.Colors.textSecondary
                        )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            currentPrimaryPhase == .resolved
            ? DesignSystem.Colors.success.opacity(0.04)
            : accent.opacity(0.02)
        )
    }

    func phaseNode(_ phase: DebugFlowPhase, isCompleted: Bool, isCurrent: Bool, isFuture: Bool) -> some View {
        let nodeColor: Color = {
            if isCompleted { return DesignSystem.Colors.success }
            if isCurrent { return accent }
            return DesignSystem.Colors.textTertiary.opacity(0.5)
        }()

        return VStack(spacing: 4) {
            ZStack {
                if isCurrent {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 22, height: 22)

                    Circle()
                        .fill(accent.opacity(0.08))
                        .frame(width: 28, height: 28)
                        .modifier(PulseModifier())
                }

                Image(systemName: isCompleted ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                    .font(.system(size: isCurrent ? 13 : 11, weight: .medium))
                    .foregroundStyle(nodeColor)
            }
            .frame(width: 28, height: 28)

            Text(shortLabel(for: phase))
                .font(.system(size: 8.5, weight: isCurrent ? .bold : .medium, design: .monospaced))
                .foregroundStyle(nodeColor)
        }
        .onHover { hovering in
            hoveredPhase = hovering ? phase : nil
        }
    }

    func phaseConnector(isCompleted: Bool) -> some View {
        VStack {
            Rectangle()
                .fill(
                    isCompleted
                    ? DesignSystem.Colors.success.opacity(0.5)
                    : DesignSystem.Colors.borderSubtle
                )
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
    }

    var shouldShowFixSubpipeline: Bool {
        debugStore.phase == .fixing
        || debugStore.phase == .instrumenting
        || debugStore.phase == .verifying
        || debugStore.phase == .resolved
        || !debugStore.hypotheses.isEmpty
        || !debugStore.instrumentationPoints.isEmpty
        || !debugStore.runtimeLogs.isEmpty
    }

    var fixSubPipeline: some View {
        let hasHypothesis = !debugStore.hypotheses.isEmpty
        let hasInstrumentation = !debugStore.instrumentationPoints.isEmpty
        let hasObservation = !debugStore.runtimeLogs.isEmpty
        let fixCompleted = debugStore.phase == .verifying || debugStore.phase == .resolved

        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            subPipelineStep(
                "Hypothesize",
                icon: "lightbulb",
                isCompleted: hasHypothesis || fixCompleted,
                isCurrent: debugStore.phase == .fixing && !hasHypothesis
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))

            subPipelineStep(
                "Instrument",
                icon: "wrench",
                isCompleted: hasInstrumentation || fixCompleted,
                isCurrent: debugStore.phase == .instrumenting || (debugStore.phase == .fixing && hasHypothesis && !hasInstrumentation)
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))

            subPipelineStep(
                "Observe",
                icon: "eye",
                isCompleted: hasObservation || fixCompleted,
                isCurrent: (debugStore.phase == .fixing || debugStore.phase == .instrumenting) && hasInstrumentation && !hasObservation
            )

            Spacer()

            if debugStore.fixLoopIteration > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                    Text("×\(debugStore.fixLoopIteration)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.warning.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    func subPipelineStep(_ label: String, icon: String, isCompleted: Bool, isCurrent: Bool) -> some View {
        let color: Color = isCompleted
        ? DesignSystem.Colors.success
        : (isCurrent ? accent : DesignSystem.Colors.textTertiary)

        return HStack(spacing: 4) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 8))
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: isCurrent ? .bold : .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isCurrent ? 0.12 : 0.06))
        )
    }

    func shortLabel(for phase: DebugFlowPhase) -> String {
        switch phase {
        case .describing: return "ANALYZE"
        case .reproducing: return "REPRO"
        case .fixing, .instrumenting: return "FIX"
        case .verifying: return "VERIFY"
        case .resolved: return "DONE"
        case .idle: return ""
        }
    }

    var phaseDetailLabel: String {
        switch debugStore.phase {
        case .idle:          return ""
        case .describing:    return "Analyzing the problem and gathering context…"
        case .reproducing:   return "Waiting for bug reproduction…"
        case .fixing:        return "Applying fix hypotheses…"
        case .instrumenting: return "Instrumenting code to observe behavior…"
        case .verifying:     return "Verifying the fix and running checks…"
        case .resolved:      return "Debug session resolved."
        }
    }
}
