import Foundation

extension CodexCLIProvider {
    static func isFailureMCPToolStatus(_ normalizedStatus: String) -> Bool {
        let failureStatuses: Set<String> = [
            "failed", "error", "cancelled", "canceled", "aborted",
            "timeout", "timed_out",
        ]
        return failureStatuses.contains(normalizedStatus)
    }

    static func normalizeIDEStateMCPTool(_ rawTool: String) -> String {
        var normalized = rawTool
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.hasPrefix("functions.") {
            normalized = String(normalized.dropFirst("functions.".count))
        }

        if normalized.hasPrefix("function.") {
            normalized = String(normalized.dropFirst("function.".count))
        }

        if normalized.hasPrefix("mcp__"),
           let namespaceSeparator = normalized.range(of: "__", options: .backwards) {
            let candidate = String(normalized[namespaceSeparator.upperBound...])
            if !candidate.isEmpty {
                normalized = candidate
            }
        }

        if let suffix = normalized.split(whereSeparator: { separator in
            separator == "." || separator == "/" || separator == ":" || separator == "\\"
        }).last {
            normalized = String(suffix)
        }

        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }

        if normalized.hasPrefix("coderide_") {
            normalized = String(normalized.dropFirst("coderide_".count))
        }

        return normalized
    }

    static func isTerminalMCPToolStatus(_ normalizedStatus: String) -> Bool {
        let successfulTerminalStatuses: Set<String> = [
            "completed", "success", "done", "ok",
        ]
        return successfulTerminalStatuses.contains(normalizedStatus) || isFailureMCPToolStatus(normalizedStatus)
    }
}
