import Foundation

enum PlanScreeningDecision: Equatable {
    case planNeeded
    case noPlanNeeded
    case unknown
}

func parsePlanScreeningDecision(from text: String) -> PlanScreeningDecision {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if normalized.hasSuffix("NO_PLAN_NEEDED") {
        return .noPlanNeeded
    }

    if normalized.hasSuffix("PLAN_NEEDED") {
        return .planNeeded
    }

    return .unknown
}

func planScreeningStatusMessage(for decision: PlanScreeningDecision) -> String {
    switch decision {
    case .planNeeded, .unknown:
        return "Starting codebase analysis..."
    case .noPlanNeeded:
        return "Request looks straightforward. Continuing..."
    }
}
