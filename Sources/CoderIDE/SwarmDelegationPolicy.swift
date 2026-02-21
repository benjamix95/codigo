import Foundation

enum SwarmDelegationDecision: Equatable {
    case autoDelegate
    case noDelegate
}

struct SwarmDelegationEvaluation: Equatable {
    let decision: SwarmDelegationDecision
    let reason: String
}

struct SwarmDelegationPolicyEvaluator {
    private static let explicitDelegationSignals: [String] = [
        "swarm",
        "multi-agent",
        "multi agent",
        "parallel",
        "in parallelo",
        "delega allo swarm",
        "parallelizza"
    ]

    private static let multiFlowSignals: [String] = [
        "in parallelo",
        "parallel",
        "parallelizza",
        "sottotask",
        "subtask",
        "indipendent",
        "cross-modulo",
        "cross modulo",
        "piu aree",
        "più aree",
        "piu moduli",
        "più moduli",
        "ampia area"
    ]

    private static let highEffortSignals: [String] = [
        "refactor",
        "rifattorizza",
        "review tecnica",
        "review approfondita",
        "test articolati",
        "integrazione",
        "migrazione",
        "security audit",
        "analisi sicurezza"
    ]

    private static let specialistRoles: [String] = [
        "planner",
        "coder",
        "reviewer",
        "debugger",
        "testwriter",
        "test writer",
        "docwriter",
        "doc writer",
        "securityauditor",
        "security auditor"
    ]

    func evaluate(
        userPrompt: String,
        suggestedTask: String,
        isAutoDelegateEnabled: Bool,
        mode: CoderMode
    ) -> SwarmDelegationEvaluation {
        guard mode == .agent else {
            return SwarmDelegationEvaluation(
                decision: .noDelegate,
                reason: "delega disattivata fuori dalla modalità Agent"
            )
        }

        guard isAutoDelegateEnabled else {
            return SwarmDelegationEvaluation(
                decision: .noDelegate,
                reason: "auto-delega swarm disattivata nelle impostazioni"
            )
        }

        let normalizedUser = normalize(userPrompt)
        let normalizedTask = normalize(suggestedTask)

        if containsAnySignal(in: normalizedUser, from: Self.explicitDelegationSignals) {
            return SwarmDelegationEvaluation(
                decision: .autoDelegate,
                reason: "richiesta esplicita di delega/parallelismo"
            )
        }

        if hasHighEffortTraits(task: normalizedTask) {
            return SwarmDelegationEvaluation(
                decision: .autoDelegate,
                reason: "task ad alto effort con parallelizzazione o ruoli multipli"
            )
        }

        return SwarmDelegationEvaluation(
            decision: .noDelegate,
            reason: "task lineare: gestibile in single-agent"
        )
    }

    private func hasHighEffortTraits(task: String) -> Bool {
        let hasMultiFlowSignals = containsAnySignal(in: task, from: Self.multiFlowSignals)
        let hasHighEffortSignals = containsAnySignal(in: task, from: Self.highEffortSignals)
        let roleCount = countDistinctRoles(in: task)

        if roleCount >= 2 { return true }
        if hasMultiFlowSignals && hasHighEffortSignals { return true }
        if hasMultiFlowSignals && task.count >= 140 { return true }
        return false
    }

    private func countDistinctRoles(in text: String) -> Int {
        var found = Set<String>()
        for role in Self.specialistRoles where text.contains(role) {
            found.insert(role.replacingOccurrences(of: " ", with: ""))
        }
        return found.count
    }

    private func containsAnySignal(in text: String, from signals: [String]) -> Bool {
        signals.contains { text.contains($0) }
    }

    private func normalize(_ input: String) -> String {
        input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
