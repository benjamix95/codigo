import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func syncStructuredFindingsFromChatResponse(
        messageId: UUID,
        sessionId: String? = nil
    ) async {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let originalContent = chatMessages[index].content
        let extraction = extractChatFindingsPayload(from: originalContent)
        guard let extraction else { return }

        chatMessages[index].content = extraction.visibleContent
        persistChatState()

        guard let sessionId = sessionId ?? selectedSessionId,
              let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
              ) else {
            return
        }

        let merge = mergeChatFindings(
            existing: snapshot.findings,
            incoming: extraction.findings
        )

        guard !merge.inserted.isEmpty else {
            return
        }

        let events = merge.inserted.map {
            CodeReviewSessionEvent.findingAdded(
                findingId: $0.id,
                severity: $0.severity.rawValue,
                filePath: $0.filePath
            )
        }
        let updated = snapshot.copying(
            findings: merge.all,
            events: snapshot.events + events,
            outcome: snapshot.copying(findings: merge.all).buildOutcomeSummary()
        )
        taskActivityStore.scheduleCodeReviewSnapshotIngest(
            updated,
            conversationId: conversationId
        )
        appendPanelSystemMessage(
            "Synced \(merge.inserted.count) finding(s) from chat into the Findings tab.",
            kind: .statusNote,
            selectChatTab: false
        )
    }

    private func extractChatFindingsPayload(
        from content: String
    ) -> (visibleContent: String, findings: [CodeReviewFinding])? {
        let pattern = #"```review_findings\s*(?:\r?\n)(\{[\s\S]*?\})\s*(?:\r?\n)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let jsonRange = Range(match.range(at: 1), in: content),
              let fullRange = Range(match.range(at: 0), in: content)
        else {
            return nil
        }

        let json = String(content[jsonRange])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFindings = object["findings"] as? [[String: Any]]
        else {
            return nil
        }

        let findings = rawFindings.compactMap(parseChatFinding)
        guard !findings.isEmpty else { return nil }

        var visible = content
        visible.removeSubrange(fullRange)
        visible = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        return (visible, findings)
    }

    private func parseChatFinding(_ raw: [String: Any]) -> CodeReviewFinding? {
        guard let file = raw["file"] as? String,
              let message = raw["message"] as? String else {
            return nil
        }
        let severity = raw["severity"] as? String ?? "warning"
        let category = raw["category"] as? String
        let line = raw["line"] as? Int
        let confidence = raw["confidence"] as? Double
        let suggestedFix = raw["suggested_fix"] as? String
        let baseFinding = CodeReviewFinding.fromRawTask(
            id: "chat-\(UUID().uuidString.prefix(8))",
            description: message,
            files: [file],
            severity: severity,
            category: category,
            origin: .reviewer,
            filePath: file,
            lineNumber: line,
            confidence: confidence,
            evidence: "Structured findings block from review panel chat",
            sourceTool: "review-panel-chat",
            blocking: nil
        )
        return CodeReviewFinding(
            id: baseFinding.id,
            severity: baseFinding.severity,
            category: baseFinding.category,
            origin: baseFinding.origin,
            filePath: baseFinding.filePath,
            lineNumber: baseFinding.lineNumber,
            endLineNumber: baseFinding.endLineNumber,
            message: baseFinding.message,
            suggestedFix: suggestedFix,
            confidence: baseFinding.confidence,
            evidence: baseFinding.evidence,
            sourceTool: baseFinding.sourceTool,
            blocking: baseFinding.blocking
        )
    }

    private func mergeChatFindings(
        existing: [CodeReviewFinding],
        incoming: [CodeReviewFinding]
    ) -> (all: [CodeReviewFinding], inserted: [CodeReviewFinding]) {
        var seen = Set(existing.map(chatFindingKey))
        var merged = existing
        var inserted: [CodeReviewFinding] = []
        for finding in incoming {
            let key = chatFindingKey(finding)
            if seen.insert(key).inserted {
                merged.append(finding)
                inserted.append(finding)
            }
        }
        return (merged, inserted)
    }

    private func chatFindingKey(_ finding: CodeReviewFinding) -> String {
        [
            finding.filePath.lowercased(),
            String(finding.lineNumber ?? 0),
            finding.category.rawValue,
            finding.message.lowercased(),
        ].joined(separator: "|")
    }
}
