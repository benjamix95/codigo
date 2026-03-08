import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func syncStructuredFindingsFromChatResponse(messageId: UUID) async {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let originalContent = chatMessages[index].content
        let extraction = extractChatFindingsPayload(from: originalContent)
        guard let extraction else { return }

        chatMessages[index].content = extraction.visibleContent
        persistChatState()

        guard let sessionId = selectedSessionId,
              let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
              ) else {
            return
        }

        let merged = mergeChatFindings(
            existing: snapshot.candidates,
            incoming: extraction.findings
        )
        let updated = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: snapshot.findings,
            candidates: merged,
            patches: snapshot.patches,
            events: snapshot.events + [
                CodeReviewSessionEvent(
                    type: .candidateAdded,
                    detail: "Chat response synced \(extraction.findings.count) candidate(s)",
                    metadata: ["source": "review-panel-chat"]
                ),
            ],
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            audit: snapshot.audit,
            outcome: snapshot.copying(candidates: merged).buildOutcomeSummary(),
            lastUpdatedAt: Date()
        )
        taskActivityStore.ingestCodeReviewSnapshot(
            updated,
            conversationId: conversationId
        )
        appendPanelSystemMessage(
            "Synced \(extraction.findings.count) candidate(s) from chat into the review workflow.",
            kind: .statusNote,
            selectChatTab: false
        )
    }

    private func extractChatFindingsPayload(
        from content: String
    ) -> (visibleContent: String, findings: [ReviewCandidate])? {
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

    private func parseChatFinding(_ raw: [String: Any]) -> ReviewCandidate? {
        guard let file = raw["file"] as? String,
              let message = raw["message"] as? String else {
            return nil
        }
        let severity = raw["severity"] as? String ?? "warning"
        let category = raw["category"] as? String
        let line = raw["line"] as? Int
        let confidence = raw["confidence"] as? Double
        let suggestedFix = raw["suggested_fix"] as? String
        let finding = CodeReviewFinding.fromRawTask(
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
        return ReviewCandidateVerificationService.candidate(
            from: CodeReviewFinding(
                id: finding.id,
                severity: finding.severity,
                category: finding.category,
                origin: finding.origin,
                filePath: finding.filePath,
                lineNumber: finding.lineNumber,
                endLineNumber: finding.endLineNumber,
                message: finding.message,
                suggestedFix: suggestedFix,
                confidence: finding.confidence,
                evidence: finding.evidence,
                sourceTool: finding.sourceTool
            ),
            signalType: .manual
        )
    }

    private func mergeChatFindings(
        existing: [ReviewCandidate],
        incoming: [ReviewCandidate]
    ) -> [ReviewCandidate] {
        var seen = Set(existing.map(chatFindingKey))
        var merged = existing
        for finding in incoming {
            let key = chatFindingKey(finding)
            if seen.insert(key).inserted {
                merged.append(finding)
            }
        }
        return merged
    }

    private func chatFindingKey(_ finding: ReviewCandidate) -> String {
        [
            finding.filePath.lowercased(),
            String(finding.lineNumber ?? 0),
            finding.category.rawValue,
            finding.message.lowercased(),
        ].joined(separator: "|")
    }
}
