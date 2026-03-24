import Foundation

/// Pure function that transforms a `SwarmLiveCardState` transcript into
/// `[SubagentChatSegment]` for rendering. Merges consecutive entries of
/// the same kind into single segments (e.g. multiple reasoning → one block).
enum SubagentChatSegmentBuilder {

    static func build(from card: SwarmLiveCardState) -> [SubagentChatSegment] {
        var segments: [SubagentChatSegment] = []
        var pendingReasoning: [ReasoningBlock] = []
        var pendingText: [String] = []
        var pendingActivities: [ToolTraceEvent] = []
        var sequence = 0

        func flushReasoning(isLive: Bool = false) {
            guard !pendingReasoning.isEmpty else { return }
            let id = pendingReasoning.first?.id ?? UUID().uuidString
            segments.append(.reasoning(id: id, blocks: pendingReasoning, isLive: isLive))
            pendingReasoning.removeAll()
        }

        func flushText(isStreaming: Bool = false) {
            guard !pendingText.isEmpty else { return }
            let joined = pendingText.joined(separator: "\n\n")
            let id = "text-\(sequence)"
            segments.append(.text(id: id, content: joined, isStreaming: isStreaming))
            pendingText.removeAll()
        }

        func flushActivities() {
            guard !pendingActivities.isEmpty else { return }
            let id = pendingActivities.first.map { "\($0.id)" } ?? "act-\(sequence)"
            segments.append(.toolTrace(id: id, events: pendingActivities))
            pendingActivities.removeAll()
        }

        for entry in card.transcript {
            sequence += 1

            switch entry.kind {
            case .userPrompt:
                flushReasoning()
                flushText()
                flushActivities()
                segments.append(.taskPrompt(id: entry.id, text: entry.detail))

            case .reasoning:
                flushText()
                flushActivities()
                pendingReasoning.append(
                    ReasoningBlock(id: entry.id, text: entry.detail)
                )

            case .assistantText:
                flushReasoning()
                flushActivities()
                pendingText.append(entry.detail)

            case .activity:
                flushReasoning()
                flushText()
                pendingActivities.append(
                    synthesizeToolTraceEvent(from: entry, sequence: sequence)
                )

            case .result:
                flushReasoning()
                flushText()
                flushActivities()
                segments.append(.result(
                    id: entry.id,
                    text: entry.detail,
                    timestamp: entry.timestamp
                ))
            }
        }

        // Flush remaining pending items
        let isLive = card.status == .running
        flushReasoning(isLive: isLive)
        flushText(isStreaming: isLive && !pendingText.isEmpty)
        flushActivities()

        // Append live text if no assistant text in transcript yet
        if isLive {
            let liveText = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasAssistantText = card.transcript.contains { $0.kind == .assistantText }
            if !liveText.isEmpty && !hasAssistantText {
                segments.append(.text(
                    id: "live-\(card.swarmId)",
                    content: String(liveText.suffix(4000)),
                    isStreaming: true
                ))
            }
        }

        return segments
    }

    // MARK: - ToolTraceEvent Synthesis

    private static func synthesizeToolTraceEvent(
        from entry: SubagentTranscriptEntry,
        sequence: Int
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            id: UUID(uuidString: entry.id) ?? UUID(),
            sequence: sequence,
            timestamp: entry.timestamp ?? Date(),
            providerId: "subagent",
            conversationId: UUID(),
            assistantMessageId: UUID(),
            type: mapActivityType(entry.title),
            title: entry.title,
            detail: entry.detail.isEmpty ? nil : entry.detail,
            payload: [:],
            phase: entry.isRunning ? .executing : .searching,
            isRunning: entry.isRunning,
            groupId: nil,
            rawKind: "subagent_activity"
        )
    }

    private static func mapActivityType(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("read") || lower.contains("file") { return "read" }
        if lower.contains("edit") || lower.contains("write") { return "edit" }
        if lower.contains("search") || lower.contains("grep") || lower.contains("glob") {
            return "web_search"
        }
        if lower.contains("bash") || lower.contains("command") || lower.contains("terminal") {
            return "command_execution"
        }
        if lower.contains("mcp") { return "mcp_tool_call" }
        return "agent"
    }
}
