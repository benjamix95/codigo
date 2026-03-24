import CoderEngine
import Foundation

private enum InlineTodoWriteMatcher {
    static let regex = try? NSRegularExpression(
        pattern: #"\[CODERIDE:todo_write\|([^\]]+)\]"#,
        options: [.caseInsensitive]
    )
}

func inlinePolicyAckHashesForStreamingUpdate(
    existingContent: String?,
    incomingContent: String,
    isReplacement: Bool
) -> [String] {
    guard !incomingContent.isEmpty else { return [] }
    let combinedContent = isReplacement
        ? incomingContent
        : (existingContent ?? "") + incomingContent
    return inlinePolicyAckHashes(in: combinedContent)
}

func inlineTodoWritePayloadsForStreamingUpdate(
    existingContent: String?,
    incomingContent: String,
    isReplacement: Bool
) -> [[String: String]] {
    guard !incomingContent.isEmpty,
          let regex = InlineTodoWriteMatcher.regex else {
        return []
    }

    let prefix = isReplacement ? "" : (existingContent ?? "")
    let combinedContent = prefix + incomingContent
    let nsContent = combinedContent as NSString
    let prefixLength = (prefix as NSString).length

    var payloads: [[String: String]] = []
    let matches = regex.matches(
        in: combinedContent,
        range: NSRange(location: 0, length: nsContent.length)
    )

    for match in matches where match.numberOfRanges >= 2 {
        if !isReplacement, match.range.location + match.range.length <= prefixLength {
            continue
        }
        let rawArgs = nsContent.substring(with: match.range(at: 1))
        let payload = parseInlineCoderideKeyValueArgs(rawArgs)
        guard EventNormalizer.parseTodoWrite(payload: payload) != nil else { continue }
        payloads.append(payload)
    }
    return payloads
}

func pipelineSwarmPayload(
    taskId: String,
    agentName: String?,
    status: String
) -> [String: String] {
    var payload: [String: String] = [
        "task_id": taskId,
        "swarm_id": taskId,
        "group_id": "swarm-\(taskId)",
        "status": status,
        "owner_kind": "worker",
        "presentation_role": "subagent",
    ]
    let normalizedAgentName = (agentName ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedAgentName.isEmpty {
        payload["agent_name"] = normalizedAgentName
    }
    return payload
}

func parseInlineCoderideKeyValueArgs(_ rawArgs: String) -> [String: String] {
    var payload: [String: String] = [:]
    for segment in rawArgs.split(separator: "|", omittingEmptySubsequences: false) {
        let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { continue }
        payload[key] = value
    }
    return payload
}
