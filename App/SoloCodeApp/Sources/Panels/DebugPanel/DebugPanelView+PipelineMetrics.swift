import SwiftUI

// MARK: - Metrics Row

extension DebugPanelView {

    var pipelineMetricsRow: some View {
        HStack(spacing: 8) {
            pipelineMetricChip(
                "Hypotheses",
                value: "\(debugStore.activeHypotheses.count)/\(debugStore.hypotheses.count)"
            )
            pipelineMetricChip(
                "Markers",
                value: "\(debugStore.debugMarkers.count)"
            )
            pipelineMetricChip(
                "Findings",
                value: "\(debugStore.openFindingsCount)/\(debugStore.debugFindings.count)"
            )
            pipelineMetricChip(
                "Logs",
                value: "\(debugStore.runtimeLogs.count)"
            )
        }
    }

    func pipelineMetricChip(_ title: String, value: String) -> some View {
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
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

// MARK: - Gates Row

extension DebugPanelView {

    @ViewBuilder
    var pipelineGatesRow: some View {
        let gates = activePipelineGates
        if !gates.isEmpty {
            HStack(spacing: 8) {
                ForEach(gates, id: \.title) { gate in
                    HStack(spacing: 5) {
                        Image(systemName: gate.ready ? "checkmark.seal.fill" : "clock.fill")
                            .font(.system(size: 8))
                        Text(gate.title)
                            .font(.system(size: 8.5, weight: .medium))
                    }
                    .foregroundStyle(
                        gate.ready ? DesignSystem.Colors.success : DesignSystem.Colors.warning
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        (gate.ready ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                            .opacity(0.12),
                        in: Capsule()
                    )
                }
            }
        }
    }

    var activePipelineGates: [PipelineGateInfo] {
        var gates: [PipelineGateInfo] = []
        if debugStore.isAwaitingReproduceConfirmation || debugStore.userConfirmedReproduce {
            gates.append(PipelineGateInfo(
                title: "Reproduce",
                ready: debugStore.userConfirmedReproduce
            ))
        }
        if debugStore.isAwaitingFixConfirmation {
            gates.append(PipelineGateInfo(title: "Fix Confirm", ready: false))
        }
        if debugStore.awaitingDebugClean {
            gates.append(PipelineGateInfo(title: "Cleanup", ready: false))
        }
        if debugStore.phase == .resolved {
            gates.append(PipelineGateInfo(title: "Resolved", ready: true))
        }
        return gates
    }
}

// MARK: - Computed Helpers

extension DebugPanelView {

    var pipelineTitle: String {
        if debugStore.phase == .resolved {
            return "Debug Session - Resolved"
        }
        if !debugStore.errorSummary.isEmpty {
            let trimmed = debugStore.errorSummary.prefix(60)
            return String(trimmed) + (debugStore.errorSummary.count > 60 ? "..." : "")
        }
        return "Debug Session"
    }

    var pipelineStepNumber: Int {
        min(debugStore.phase.phaseIndex + 1, pipelineTotalSteps)
    }

    var pipelineTotalSteps: Int {
        DebugFlowPhase.mainPhases.count
    }

    var pipelineProgressPercent: Int {
        let total = pipelineTotalSteps
        guard total > 0 else { return 0 }
        if debugStore.phase == .resolved { return 100 }
        return Int(Double(debugStore.phase.phaseIndex) / Double(total) * 100)
    }

    var pipelineCurrentPhaseColor: Color {
        switch debugStore.phase {
        case .idle:          return .secondary
        case .describing:    return DesignSystem.Colors.info
        case .reproducing:   return DesignSystem.Colors.warning
        case .fixing:        return accent
        case .instrumenting: return accent
        case .verifying:     return DesignSystem.Colors.success
        case .resolved:      return DesignSystem.Colors.success
        }
    }

    var pipelineSummaryText: String {
        switch debugStore.phase {
        case .idle:
            return ""
        case .describing:
            return "L'agente sta analizzando log, errori e stack trace per descrivere il bug."
        case .reproducing:
            if debugStore.isAwaitingReproduceConfirmation {
                return "In attesa che tu riproduca il problema con i marker inseriti."
            }
            return "L'agente sta preparando l'ambiente per riprodurre il bug."
        case .fixing:
            let iter = debugStore.fixLoopIteration
            if iter > 1 {
                return "Iterazione \(iter) del ciclo fix: ipotesi, strumenti, osserva, correggi."
            }
            return "L'agente sta formulando ipotesi e applicando correzioni."
        case .instrumenting:
            return "Inserimento di logging e asserzioni per osservare il comportamento."
        case .verifying:
            if debugStore.awaitingDebugClean {
                return "In attesa di rimuovere i marker di debug prima di risolvere."
            }
            return "Verifica della correzione: test e controllo regressioni."
        case .resolved:
            if !debugStore.resolutionSummary.isEmpty {
                return debugStore.resolutionSummary
            }
            return "Il bug e' stato risolto con successo."
        }
    }
}

// MARK: - Gate Info

struct PipelineGateInfo {
    let title: String
    let ready: Bool
}
