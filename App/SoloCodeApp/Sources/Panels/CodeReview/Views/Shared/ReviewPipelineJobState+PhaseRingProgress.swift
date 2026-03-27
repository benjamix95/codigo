import Foundation

extension ReviewPipelineJobState {
    /// Anello circolare: **0…100 nell’ambito della sola fase corrente**. Cambiando fase riparte da 0.
    /// Avanza **in base ai dati che arrivano** (snapshot); tra un valore e l’altro SwiftUI interpola l’anello.
    /// I tool in **running** contribuiscono con una frazione così la percentuale non resta bloccata a scatti solo su 0 / 33 / 66.
    var displayProgressPercent: Int {
        let raw: Int
        switch phase {
        case "queued":
            raw = queuedPhaseRingProgress()
        case "discovery":
            raw = discoveryPhaseRingProgress()
        case "audit":
            raw = auditPhaseRingProgress()
        case "verification":
            raw = verificationPhaseRingProgress()
        case "patch_preparation":
            raw = patchPreparationPhaseRingProgress()
        case "publish_ready":
            raw = publishReadyPhaseRingProgress()
        case "completed":
            raw = 100
        default:
            raw = fallbackPhaseRingProgress()
        }
        let clamped = min(100, max(0, raw))
        #if DEBUG
        ReviewPanelDebugNDJSON.emitThrottled(
            key: "phaseRing",
            minInterval: 1.05,
            hypothesisId: "H_ring_zero",
            location: "ReviewPipelineJobState+PhaseRingProgress.displayProgressPercent",
            message: "phase_ring",
            data: [
                "phase": phase,
                "pct": clamped,
                "toolsCompleted": toolsCompleted,
                "toolsRunning": toolsRunning,
                "toolsTotal": toolsTotal,
                "candidateCount": candidateCount,
                "toolStatuses": tools.map { String(describing: $0.status) }.joined(separator: ","),
            ]
        )
        #endif
        return clamped
    }

    var displayProgressText: String { "\(displayProgressPercent)%" }

    // MARK: - Tool row (granularità > soli toolsCompleted / toolsTotal)

    /// Peso 0…1: solo **completati** contano; `running` non gonifica l’anello prima del lavoro effettivo.
    private func toolExecutionWeightedPercent() -> Int? {
        guard !tools.isEmpty else { return nil }
        var sum = 0.0
        for tool in tools {
            switch tool.status {
            case .completed:
                sum += 1.0
            case .running, .pending:
                sum += 0.0
            }
        }
        let pct = (sum / Double(tools.count)) * 100.0
        return Int(round(pct))
    }

    private func mergedToolProgress(discoveryBoost: Int = 0) -> Int {
        if let weighted = toolExecutionWeightedPercent() {
            let core = min(100, weighted)
            if discoveryBoost > 0 { return min(100, max(core, discoveryBoost)) }
            return core
        }
        let t = max(toolsTotal, 1)
        var fromCounts = toolsCompleted * 100 / t
        if toolsRunning > 0, toolsCompleted > 0, toolsCompleted < t {
            let runningShare = min(55, (toolsRunning * 100) / max(t * 2, 1))
            fromCounts = min(100, fromCounts + runningShare)
        } else {
            fromCounts = min(100, fromCounts)
        }
        if discoveryBoost > 0 { return min(100, max(fromCounts, discoveryBoost)) }
        return fromCounts
    }

    // MARK: - Per fase

    private func queuedPhaseRingProgress() -> Int {
        mergedToolProgress()
    }

    private func discoveryPhaseRingProgress() -> Int {
        let candidateHint =
            toolsCompleted > 0 && candidateCount > 0
                ? min(30 + candidateCount * 4, 92)
                : 0
        return mergedToolProgress(discoveryBoost: candidateHint)
    }

    private func auditPhaseRingProgress() -> Int {
        mergedToolProgress()
    }

    private func verificationPhaseRingProgress() -> Int {
        let denom = max(candidateCount + verifiedCount, 1)
        let exact = (Double(verifiedCount) / Double(denom)) * 100.0
        return Int(round(exact))
    }

    private func patchPreparationPhaseRingProgress() -> Int {
        let v = max(verifiedCount, 1)
        if publishedFindingCount > 0 {
            let exact = (Double(publishedFindingCount) / Double(v)) * 100.0
            return min(100, Int(round(exact)))
        }
        if gates.contains(where: { $0.title == "Patch" && $0.isReady }) {
            return 100
        }
        // Prima il fattore 85 bloccava l’anello a ~85% anche con tutti i verified e i tool completati (log H_ring_zero).
        let fromVerified = (Double(min(verifiedCount, v * 3)) / Double(v)) * 100.0
        let verifiedPct = min(100, max(0, Int(round(fromVerified))))
        if let toolPct = toolExecutionWeightedPercent() {
            return min(100, max(verifiedPct, toolPct))
        }
        return verifiedPct
    }

    private func publishReadyPhaseRingProgress() -> Int {
        let denom = max(verifiedCount, max(publishedFindingCount, 1))
        if publishedFindingCount > 0 {
            let exact = (Double(publishedFindingCount) / Double(denom)) * 100.0
            return min(100, Int(round(exact)))
        }
        let ready = gates.filter(\.isReady).count
        let total = max(gates.count, 1)
        return min(100, Int(round((Double(ready) / Double(total)) * 100.0)))
    }

    private func fallbackPhaseRingProgress() -> Int {
        if let w = toolExecutionWeightedPercent() { return w }
        let t = max(toolsTotal, 1)
        if toolsTotal > 0 {
            return min(100, toolsCompleted * 100 / t)
        }
        return min(100, max(0, progressPercent))
    }
}
