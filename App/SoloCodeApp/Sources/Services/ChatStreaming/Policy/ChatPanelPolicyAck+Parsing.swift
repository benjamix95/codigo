import Foundation

private enum InlinePolicyAckMatcher {
    static let regex = try? NSRegularExpression(
        pattern: #"\[CODERIDE:policy_ack\|[^\]]*?\bhash=([^\]\|\s]+)[^\]]*\]"#,
        options: [.caseInsensitive]
    )
}

enum PolicyAckDisposition: Equatable {
    case acknowledged
    case invalid
    case ignored
}

func policyAckDisposition(status: String?) -> PolicyAckDisposition {
    let normalized = (status ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    switch normalized {
    case "acknowledged":
        return .acknowledged
    case "invalid":
        return .invalid
    default:
        return .ignored
    }
}

func inlinePolicyAckHashes(in content: String) -> [String] {
    guard !content.isEmpty,
          let regex = InlinePolicyAckMatcher.regex else {
        return []
    }

    let nsContent = content as NSString
    let matches = regex.matches(
        in: content,
        range: NSRange(location: 0, length: nsContent.length)
    )

    var ordered: [String] = []
    var seen: Set<String> = []
    for match in matches where match.numberOfRanges >= 2 {
        let hash = nsContent.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty, !seen.contains(hash) else { continue }
        seen.insert(hash)
        ordered.append(hash)
    }
    return ordered
}

func shouldBypassPolicyAckLiveVisibilityGate(
    type rawType: String,
    payload: [String: String]
) -> Bool {
    let type = rawType
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let directTypes: Set<String> = [
        "assistant_update",
        "agent",
        "subagent_text",
        "reasoning",
        "bash",
        "command_execution",
        "file_change",
        "edit",
        "search",
        "semantic_search",
        "instant_grep",
        "mcp_tool_call",
        "skill_invocation",
        "permission_denied",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "error",
    ]
    if directTypes.contains(type) { return true }
    if ["web_search", "web_fetch", "read_batch", "debug_", "plan_"].contains(where: type.hasPrefix) {
        return true
    }
    return payload["swarm_id"] != nil && (type == "agent" || type == "subagent_text")
}
