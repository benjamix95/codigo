import Foundation
import CoderEngine

extension ChatStore {
    static func fallbackTaskRuntimeState(
        from request: MainChatTaskRuntimeRequestBridge
    ) -> MainChatTaskRuntimeStateBridge? {
        guard request.schemaVersion == 1 else { return nil }

        var states = request.state.taskStates

        func taskIndex(_ conversationId: String) -> Int? {
            states.firstIndex { $0.conversationId == conversationId }
        }

        switch request.operation {
        case "begin_task":
            guard let conversationId = request.conversationId else { return nil }
            if let index = taskIndex(conversationId) {
                let current = states[index]
                states[index] = MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId,
                    startedAt: request.startedAt ?? current.startedAt,
                    statusText: "Thinking"
                )
            } else {
                states.append(
                    MainChatTaskStateSnapshotBridge(
                        conversationId: conversationId,
                        startedAt: request.startedAt,
                        statusText: "Thinking"
                    )
                )
            }
        case "end_task":
            guard let conversationId = request.conversationId else { return nil }
            states.removeAll { $0.conversationId == conversationId }
        case "set_task_status":
            guard let conversationId = request.conversationId,
                  let statusText = request.statusText else { return nil }
            if let index = taskIndex(conversationId) {
                let current = states[index]
                states[index] = MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId,
                    startedAt: current.startedAt,
                    statusText: statusText
                )
            }
        default:
            return nil
        }

        states.sort {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
                || (($0.startedAt == $1.startedAt) && $0.conversationId < $1.conversationId)
        }
        return MainChatTaskRuntimeStateBridge(taskStates: states)
    }

    nonisolated private static var isRustMarkersRuntimeAvailable: Bool { ReviewCoreBridge.isEnabled }

    nonisolated static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
        let core: String
        if isRustMarkersRuntimeAvailable {
            let request = MainChatMarkersRequestBridge(
                schemaVersion: 1,
                operation: "strip_coderide_markers",
                text: content,
                aggressive: aggressive
            )
            core = RustMainChatStoreAdapter.handleMarkers(request)
                ?? swiftFallbackStripCoderideMarkers(content, aggressive: aggressive)
        } else {
            core = swiftFallbackStripCoderideMarkers(content, aggressive: aggressive)
        }
        let filtered = CoderideDisplayLineFilter.stripDisplayLinesWithCoderideToolPrefix(core)
        return aggressive ? filtered.trimmingCharacters(in: .whitespacesAndNewlines) : filtered
    }

    nonisolated static func stripStreamingCoderideMarkers(_ content: String) -> String {
        let core = swiftFallbackStripStreamingCoderideMarkers(content)
        return CoderideDisplayLineFilter.stripDisplayLinesWithCoderideToolPrefix(core)
    }

    nonisolated static func sanitizedChatReasoningText(_ text: String) -> String {
        stripCoderideMarkers(text, aggressive: true)
    }

    nonisolated static func sanitizedStreamingDetailLine(
        _ raw: String,
        ellipsis: String = "..."
    ) -> String? {
        let stripped = stripCoderideMarkers(raw, aggressive: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return stripped.count > 80 ? String(stripped.prefix(77)) + ellipsis : stripped
    }

    nonisolated static func extractLastOperationalThinkingLine(from content: String) -> String? {
        guard isRustMarkersRuntimeAvailable else { return nil }
        let request = MainChatMarkersRequestBridge(
            schemaVersion: 1,
            operation: "extract_last_operational_thinking_line",
            text: content,
            aggressive: nil
        )
        guard let result = RustMainChatStoreAdapter.handleMarkers(request) else { return nil }
        return result.isEmpty ? nil : result
    }

    nonisolated private static func swiftFallbackStripCoderideMarkers(
        _ content: String,
        aggressive: Bool
    ) -> String {
        var working = content.replacingOccurrences(
            of: "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]",
            with: "",
            options: .regularExpression
        )
        while let range = working.range(of: "[CODERIDE", options: .caseInsensitive) {
            let tail = working[range.lowerBound...]
            if let close = tail.firstIndex(of: "]") {
                working.removeSubrange(range.lowerBound...close)
            } else if let newline = tail.firstIndex(of: "\n") {
                working.removeSubrange(range.lowerBound..<newline)
            } else {
                working.removeSubrange(range.lowerBound..<working.endIndex)
                break
            }
        }
        let stripped = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return aggressive ? stripped : stripped
    }

    nonisolated private static func swiftFallbackStripStreamingCoderideMarkers(_ content: String) -> String {
        var working = content.replacingOccurrences(
            of: "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]",
            with: "",
            options: .regularExpression
        )
        while let range = working.range(of: "[CODERIDE", options: .caseInsensitive) {
            let tail = working[range.lowerBound...]
            if let close = tail.firstIndex(of: "]") {
                working.removeSubrange(range.lowerBound...close)
            } else if let newline = tail.firstIndex(of: "\n") {
                working.removeSubrange(range.lowerBound..<newline)
            } else {
                working.removeSubrange(range.lowerBound..<working.endIndex)
                break
            }
        }
        return working.replacingOccurrences(
            of: #"^(?:\r?\n)+"#,
            with: "",
            options: .regularExpression
        )
    }
}
