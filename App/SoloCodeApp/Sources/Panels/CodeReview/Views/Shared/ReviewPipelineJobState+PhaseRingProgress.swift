import Foundation

extension ReviewPipelineJobState {
    /// Anello circolare: **0…100 nell’ambito della sola fase corrente**. Cambiando fase il conteggio riparte
    /// da 0 e risale verso 100 dentro quella fase (non è un avanzamento globale del run).
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
            return 100
        default:
            raw = fallbackPhaseRingProgress()
        }
        return min(100, max(0, raw))
    }

    var displayProgressText: String { "\(displayProgressPercent)%" }

    // MARK: - Per-fase (0…100)

    private func queuedPhaseRingProgress() -> Int {
        let t = max(toolsTotal, 1)
        if toolsCompleted > 0 {
            return min(100, toolsCompleted * 100 / t)
        }
        if toolsRunning > 0 {
            return min(45, toolsRunning * 14)
        }
        return 0
    }

    private func discoveryPhaseRingProgress() -> Int {
        let t = max(toolsTotal, 1)
        if toolsCompleted > 0 {
            return min(100, toolsCompleted * 100 / t)
        }
        if toolsRunning > 0 {
            return min(95, 10 + toolsRunning * 14)
        }
        if candidateCount > 0 {
            return min(85, candidateCount * 6)
        }
        return 0
    }

    private func auditPhaseRingProgress() -> Int {
        let t = max(toolsTotal, 1)
        var pct = min(100, toolsCompleted * 100 / t)
        if toolsRunning > 0, toolsCompleted < t {
            pct = min(100, pct + min(30, toolsRunning * 9))
        }
        return pct
    }

    private func verificationPhaseRingProgress() -> Int {
        let denom = max(candidateCount + verifiedCount, 1)
        return verifiedCount * 100 / denom
    }

    private func patchPreparationPhaseRingProgress() -> Int {
        let v = max(verifiedCount, 1)
        if publishedFindingCount > 0 {
            return min(100, publishedFindingCount * 100 / v)
        }
        if let patchGate = gates.first(where: { $0.title == "Patch" }) {
            return patchGate.isReady ? 80 : min(55, verifiedCount * 10)
        }
        return min(50, verifiedCount * 9)
    }

    private func publishReadyPhaseRingProgress() -> Int {
        let denom = max(verifiedCount, max(publishedFindingCount, 1))
        if publishedFindingCount > 0 {
            return min(100, publishedFindingCount * 100 / denom)
        }
        let ready = gates.filter(\.isReady).count
        let total = max(gates.count, 1)
        return min(100, ready * 100 / total)
    }

    private func fallbackPhaseRingProgress() -> Int {
        let t = max(toolsTotal, 1)
        if toolsTotal > 0 {
            return min(100, toolsCompleted * 100 / t)
        }
        return min(100, max(0, progressPercent))
    }
}
