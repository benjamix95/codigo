import Foundation

extension ToolEnabledLLMProvider {

    func inferredToolName(from payload: [String: String]) -> String {
        let knownTools = knownExecutableToolNames()
        let explicitCandidates = [
            payload["name"],
            payload["tool"],
            payload["tool_name"],
            payload["function"],
            payload["function_name"],
        ]
        var sawExplicitCandidate = false
        for candidate in explicitCandidates {
            let rawName = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawName.isEmpty else { continue }
            sawExplicitCandidate = true
            let name = ProviderToolEventMapper.normalizeToolIdentifier(rawName)
            if name == "debug_panel" {
                // Legacy hard-cut: never execute, always route to validation error.
                return name
            }
            if name == "invoke_swarm" {
                // Legacy swarm entrypoint is adapted to subagent_* execution later.
                return name
            }
            if Self.isQualifiedMCPToolReference(name) {
                return name
            }
            if name.hasPrefix("subagent_"), SubagentRole.fromToolName(name) != nil {
                return name
            }
            if knownTools.contains(name) {
                return name
            }
        }

        // If the model explicitly named an unknown tool, avoid heuristic fallback
        // to unrelated operations (for example read/write).
        if sawExplicitCandidate {
            return ""
        }

        if let command = payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "bash"
        }
        if let query = payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inferredQueryToolName(from: payload)
        }
        if let pattern = payload["pattern"], !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "glob"
        }
        if let content = payload["content"], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "write"
        }
        if let path = payload["path"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "read"
        }
        return ""
    }

    private static let _cachedKnownToolNames: Set<String> = {
        var names = Set<String>()
        for entry in ToolSchemaCatalog.entries {
            let normalized = ProviderToolEventMapper.normalizeToolIdentifier(entry.name)
            if !normalized.isEmpty {
                names.insert(normalized)
            }
        }
        return names
    }()

    func knownExecutableToolNames() -> Set<String> {
        Self._cachedKnownToolNames
    }

    static func isQualifiedMCPToolReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy(Self.isValidMCPIdentifier)
    }

    static func isValidMCPIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Za-z0-9_.:-]{1,128}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    func shouldForceAutonomousContinuation(_ text: String, roundIndex: Int) -> Bool {
        if roundIndex >= maxAutonomousContinuationRounds { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isMeaningfulAssistantCompletion(trimmed) {
            return false
        }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let lower = trimmed.lowercased()
        let explicitSignals = [
            "let me ",
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "exploring the",
            "analyzing the",
            "next i'll",
            "next i will",
            "would you like me to",
            "if you want i can",
            "i can continue by"
        ]
        if explicitSignals.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.hasSuffix("...") || lower.hasSuffix(":") {
            return true
        }
        return false
    }

    /// Shared blocked snippets used both for delta sanitization and meaningful-completion checks.
    private static let blockedProtocolSnippets: [String] = [
        "Initial user prompt:",
        "Original user prompt:",
        "Partial transcript:",
        "Conversation transcript:",
        "Transcript:",
        "Tool results just executed:",
        "Tool results from previous round:",
        "When finished: MANDATORY",
        "When finished: you MUST provide",
        "(No tools used in the previous round.)",
        "[assistant]",
        "coderide:tool_call",
    ]

    func sanitizeVisibleDelta(_ delta: String) -> String {
        if delta.isEmpty { return "" }
        let lower = delta.lowercased()
        for snippet in Self.blockedProtocolSnippets where lower.contains(snippet.lowercased()) {
            return ""
        }
        return delta
    }

    func buildToolFallbackSummary(_ results: [[String: String]]) -> String {
        let lines = results.prefix(8).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            let path = item["path"] ?? ""
            var line = "- \(name): \(status)"
            if !detail.isEmpty { line += " — \(detail)" }
            if !path.isEmpty { line += " (\(path))" }
            return line
        }
        guard !lines.isEmpty else { return "" }
        return """

        **Summary:**
        \(lines.joined(separator: "\n"))

        """
    }

    func buildForcedFinalizationPrompt(
        originalPrompt: String,
        transcript: String,
        toolResults: [[String: String]]
    ) -> String {
        let compactResults = toolResults.prefix(10).map { item in
            let name = item["name"] ?? "tool"
            let status = item["status"] ?? "unknown"
            let detail = item["detail"] ?? ""
            return "- \(name): \(status) \(detail)"
        }.joined(separator: "\n")
        return """
        You have already executed the required tools. Now you MUST produce ONLY the final outcome for the user.
        Mandatory rules:
        1) Do NOT emit any more tool markers.
        2) Do NOT stop until you write a complete final summary.
        3) If any data is missing, state what's missing and propose a concrete next step.

        Original user prompt:
        \(originalPrompt)

        Transcript:
        \(transcript)

        Tool results:
        \(compactResults)
        """
    }

    func isMeaningfulAssistantCompletion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 24 { return false }
        let lower = trimmed.lowercased()
        for snippet in Self.blockedProtocolSnippets where lower.contains(snippet.lowercased()) {
            return false
        }
        return true
    }


}
