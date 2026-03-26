import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func mainChatTraceLoggingEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment["SOLOCODE_STREAM_TRACE"] ?? ""
    return env == "1" || env.lowercased() == "true"
}

func mainChatTraceLog(_ message: @autoclosure () -> String) {
    guard mainChatTraceLoggingEnabled() else { return }
    NSLog("[MainChatTrace] %@", message())
}

func policyAckPayloadFromEvent(
    type: String,
    payload: [String: String]
) -> [String: String]? {
    let normalizedType = type
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedType == "policy_ack" {
        return payload
    }
    guard normalizedType == "mcp_tool_call" else { return nil }
    let tool = (payload["mcp_tool"] ?? payload["tool"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedTool = tool
        .replacingOccurrences(of: "functions.", with: "")
        .replacingOccurrences(of: "function.", with: "")
    guard normalizedTool == "coderide_policy_ack" || normalizedTool == "policy_ack" else {
        return nil
    }
    let hash = (payload["hash"] ?? payload["policy_hash"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !hash.isEmpty else { return nil }
    return [
        "hash": hash,
        "title": payload["title"] ?? "Policy acknowledged",
        "detail": payload["detail"] ?? "Policy hash accepted via MCP tool call",
    ]
}

func mainChatInlineReasoningGroupId(
    providerId: String,
    payload: [String: String]
) -> String {
    if let explicit = payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !explicit.isEmpty,
       explicit == "codex-intermediate-turns" {
        return explicit
    }
    let normalizedProvider = providerId
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalizedProvider.isEmpty {
        return "reasoning-stream"
    }
    return "reasoning-stream"
}

@MainActor
func promotedAssistantUpdateContent(
    currentVisibleText: String,
    incomingRawOutput: String
) -> String? {
    let looseBoundary = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let cleaned = ChatStore.stripCoderideMarkers(incomingRawOutput, aggressive: true)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    let current = currentVisibleText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !current.isEmpty else { return cleaned }
    let looseCurrent = current.trimmingCharacters(in: looseBoundary)
    let looseCleaned = cleaned.trimmingCharacters(in: looseBoundary)

    if current == cleaned
        || current.contains(cleaned)
        || (!looseCleaned.isEmpty && (looseCurrent == looseCleaned || looseCurrent.hasPrefix(looseCleaned)))
    {
        return nil
    }
    if cleaned.hasPrefix(current) || cleaned.contains(current) {
        return cleaned
    }
    return cleaned
}
