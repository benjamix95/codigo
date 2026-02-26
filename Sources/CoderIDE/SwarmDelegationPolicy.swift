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
        "swam",
        "multi-agent",
        "multi agent",
        "parallel",
        "in parallel",
        "delegate to swarm",
        "parallelize",
        "parallelise",
        "delegate to swarm",
        "delegate to sub-agent",
        "delegate to sub agent"
    ]

    private static let multiFlowSignals: [String] = [
        "in parallel",
        "parallel",
        "parallelize",
        "parallelise",
        "subtasks",
        "sub-task",
        "subtask",
        "independent",
        "cross-module",
        "cross modulo",
        "multiple areas",
        "multiple modules",
        "wide scope",
        "workstream",
        "multiple workstreams",
        "independent tracks",
        "independent steps"
    ]

    private static let highEffortSignals: [String] = [
        "refactor",
        "technical review",
        "deep review",
        "advanced testing",
        "integration",
        "migration",
        "security audit",
        "security analysis",
        "cross-cutting",
        "cross cutting",
        "end-to-end",
        "e2e"
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

    private static let simpleTaskSignals: [String] = [
        "quick fix",
        "small fix",
        "single file",
        "one file",
        "minor change",
        "explain",
        "summarize",
        "answer only",
        "just answer"
    ]

    func evaluate(
        userPrompt: String,
        suggestedTask: String,
        isAutoDelegateEnabled: Bool,
        mode: CoderMode
    ) -> SwarmDelegationEvaluation {
        guard mode == .agent || mode == .agentSwarm else {
            return SwarmDelegationEvaluation(
                decision: .noDelegate,
                reason: "delegation disabled outside Agent/Agent Swarm mode"
            )
        }

        if mode == .agentSwarm {
            return SwarmDelegationEvaluation(
                decision: .autoDelegate,
                reason: "Agent Swarm mode enabled"
            )
        }

        guard isAutoDelegateEnabled else {
            return SwarmDelegationEvaluation(
                decision: .noDelegate,
                reason: "swarm auto-delegation disabled in settings"
            )
        }

        let normalizedUser = normalize(userPrompt)
        let normalizedTask = normalize(suggestedTask)
        let combined = "\(normalizedUser)\n\(normalizedTask)"

        if containsAnySignal(in: combined, from: Self.explicitDelegationSignals) {
            return SwarmDelegationEvaluation(
                decision: .autoDelegate,
                reason: "explicit request for swarm/sub-agent delegation"
            )
        }

        if isClearlySimpleTask(text: normalizedTask) {
            return SwarmDelegationEvaluation(
                decision: .noDelegate,
                reason: "simple or linear task; keep single-agent execution"
            )
        }

        let complexityScore = delegationComplexityScore(
            userPrompt: normalizedUser,
            suggestedTask: normalizedTask
        )
        if complexityScore >= 4 {
            return SwarmDelegationEvaluation(
                decision: .autoDelegate,
                reason: "complex multi-step scope with independent tracks or specialist roles"
            )
        }

        return SwarmDelegationEvaluation(
            decision: .noDelegate,
            reason: "task can be completed reliably in single-agent mode"
        )
    }

    private func delegationComplexityScore(userPrompt: String, suggestedTask: String) -> Int {
        let combined = "\(userPrompt)\n\(suggestedTask)"
        let hasMultiFlowSignals = containsAnySignal(in: combined, from: Self.multiFlowSignals)
        let hasHighEffortSignals = containsAnySignal(in: combined, from: Self.highEffortSignals)
        let roleCount = countDistinctRoles(in: combined)
        let wordCount = combined.split(whereSeparator: \.isWhitespace).count
        let stepCount = inferredStepCount(in: suggestedTask)
        let simpleSignals = countSignals(in: combined, from: Self.simpleTaskSignals)

        var score = 0
        if roleCount >= 2 { score += 3 }
        if hasMultiFlowSignals { score += 2 }
        if hasHighEffortSignals { score += 2 }
        if stepCount >= 3 { score += 2 }
        if wordCount >= 120 { score += 1 }
        if simpleSignals > 0 { score -= min(3, simpleSignals) }
        return score
    }

    private func isClearlySimpleTask(text: String) -> Bool {
        let hasMultiFlowSignals = containsAnySignal(in: text, from: Self.multiFlowSignals)
        let hasHighEffortSignals = containsAnySignal(in: text, from: Self.highEffortSignals)
        let roleCount = countDistinctRoles(in: text)
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let hasSimpleSignals = containsAnySignal(in: text, from: Self.simpleTaskSignals)
        let steps = inferredStepCount(in: text)

        if hasSimpleSignals && !hasMultiFlowSignals && !hasHighEffortSignals && roleCount == 0 {
            return true
        }
        if wordCount < 70 && roleCount == 0 && steps <= 2 && !hasMultiFlowSignals && !hasHighEffortSignals {
            return true
        }
        return false
    }

    private func inferredStepCount(in text: String) -> Int {
        let numbered = text.components(separatedBy: "\n").filter {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("- ") || line.hasPrefix("* ") { return true }
            return line.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }
        if !numbered.isEmpty { return numbered.count }

        let separators = [" then ", " poi ", " after ", " and then ", " -> ", " => "]
        let lowercase = text.lowercased()
        var inferred = 1
        for separator in separators where lowercase.contains(separator) {
            inferred += 1
        }
        return inferred
    }

    private func countDistinctRoles(in text: String) -> Int {
        var found = Set<String>()
        for role in Self.specialistRoles where text.contains(role) {
            found.insert(role.replacingOccurrences(of: " ", with: ""))
        }
        return found.count
    }

    private func countSignals(in text: String, from signals: [String]) -> Int {
        signals.reduce(into: 0) { total, signal in
            if text.contains(signal) {
                total += 1
            }
        }
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
