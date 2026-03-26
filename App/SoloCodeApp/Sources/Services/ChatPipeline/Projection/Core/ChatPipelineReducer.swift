import Foundation

enum ChatPipelineReducer {
    static func apply(
        state: ChatTurnState,
        event: ChatPipelineEvent
    ) -> ChatTurnState {
        var next = state
        next.sequence = max(next.sequence, event.sequence)
        next.updatedAt = event.timestamp
        if next.providerId == nil {
            next.providerId = event.payload["provider_id"] ?? event.source
        }

        switch event.kind {
        case .turnStarted:
            next.isStreaming = true
            next.status = event.payload["status"] ?? "streaming"
            next.startedAt = next.startedAt ?? event.timestamp
        case .turnCompleted:
            next.isStreaming = false
            next.status = event.payload["status"] ?? "completed"
            next.completedAt = event.timestamp
        case .turnFailed:
            next.isStreaming = false
            next.status = event.payload["status"] ?? "failed"
            next.completedAt = event.timestamp
            next = upsertStatusArtifact(
                in: next,
                id: "turn-failed",
                title: "Turn failed",
                text: event.payload["detail"] ?? event.payload["error"] ?? "Unexpected error"
            )
        case .textDelta:
            let streamId = streamId(for: event)
            next = registerStream(streamId, in: next)
            let current = next.textByStreamId[streamId, default: ""]
            next.textByStreamId[streamId] = current + (event.payload["delta"] ?? "")
        case .textReplace:
            let streamId = streamId(for: event)
            next = registerStream(streamId, in: next)
            next.textByStreamId[streamId] = event.payload["replacement"] ?? ""
        case .reasoningDelta:
            let groupId = event.payload["group_id"] ?? "reasoning"
            let current = next.reasoningByGroupId[groupId]
            let merged = ChatStreamReasoningTextMerge.merge(
                existing: current,
                incoming: event.payload["output"] ?? ""
            )
            if !merged.isEmpty {
                next.reasoningByGroupId[groupId] = merged
            }
        case .mermaidArtifact:
            let title = event.payload["title"] ?? "Diagram"
            let code = event.payload["code"] ?? ""
            if !code.isEmpty {
                next = upsertArtifact(
                    in: next,
                    ChatArtifact(
                        id: event.payload["artifact_id"] ?? "mermaid-\(next.artifacts.count)",
                        kind: .mermaid,
                        title: title,
                        text: code
                    )
                )
            }
        case .commandsArtifact:
            if let command = event.payload["command"], !command.isEmpty {
                next = appendItemArtifact(
                    in: next,
                    id: "commands",
                    kind: .commands,
                    title: "Commands executed",
                    item: command
                )
            }
        case .filesArtifact:
            if let path = event.payload["path"], !path.isEmpty {
                next = appendItemArtifact(
                    in: next,
                    id: "files",
                    kind: .files,
                    title: "Files touched",
                    item: path
                )
            }
        case .statusBadge:
            let title = event.payload["title"] ?? "Status"
            let text = event.payload["detail"] ?? event.payload["status"] ?? ""
            if !text.isEmpty {
                next = upsertStatusArtifact(in: next, id: event.payload["artifact_id"] ?? title, title: title, text: text)
            }
        case .planArtifact:
            let title = event.payload["title"] ?? "Plan"
            let text = event.payload["text"] ?? ""
            if !text.isEmpty {
                next = upsertArtifact(
                    in: next,
                    ChatArtifact(
                        id: event.payload["artifact_id"] ?? "plan-\(next.artifacts.count)",
                        kind: .plan,
                        title: title,
                        text: text
                    )
                )
            }
        case .toolTraceArtifact:
            let title = event.payload["title"] ?? "Trace summary"
            let text = event.payload["detail"] ?? ""
            if !text.isEmpty {
                next = upsertArtifact(
                    in: next,
                    ChatArtifact(
                        id: event.payload["artifact_id"] ?? "tool-trace",
                        kind: .toolTrace,
                        title: title,
                        text: text,
                        isCollapsedByDefault: true
                    )
                )
            }
        case .todoSnapshot:
            break
        }

        return next
    }

    private static func streamId(for event: ChatPipelineEvent) -> String {
        event.payload["stream_id"]
            ?? event.payload["task_id"]
            ?? event.payload["group_id"]
            ?? "main"
    }

    private static func registerStream(_ streamId: String, in state: ChatTurnState) -> ChatTurnState {
        var next = state
        if !next.orderedTextStreamIds.contains(streamId) {
            next.orderedTextStreamIds.append(streamId)
        }
        return next
    }

    private static func upsertArtifact(in state: ChatTurnState, _ artifact: ChatArtifact) -> ChatTurnState {
        var next = state
        if let index = next.artifacts.firstIndex(where: { $0.id == artifact.id }) {
            next.artifacts[index] = artifact
        } else {
            next.artifacts.append(artifact)
        }
        return next
    }

    private static func appendItemArtifact(
        in state: ChatTurnState,
        id: String,
        kind: ChatArtifactKind,
        title: String,
        item: String
    ) -> ChatTurnState {
        var artifact = state.artifacts.first(where: { $0.id == id })
            ?? ChatArtifact(id: id, kind: kind, title: title, items: [], isCollapsedByDefault: true)
        if !artifact.items.contains(item) {
            artifact.items.append(item)
        }
        return upsertArtifact(in: state, artifact)
    }

    private static func upsertStatusArtifact(
        in state: ChatTurnState,
        id: String,
        title: String,
        text: String
    ) -> ChatTurnState {
        upsertArtifact(
            in: state,
            ChatArtifact(
                id: id,
                kind: .status,
                title: title,
                text: text,
                isCollapsedByDefault: false
            )
        )
    }

}
