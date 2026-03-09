import CoderEngine
import Foundation

enum VerifiedFindingsChatPresentationService {
    static func mainChatArtifactPayload(
        payload: ReviewFindingPayload,
        snapshot: CodeReviewSessionSnapshot
    ) -> [String: String] {
        let finding = snapshot.findings.first(where: { $0.id == payload.finding.findingId })
            ?? syntheticFinding(from: payload)
        let patch = snapshot.patches.first(where: { $0.findingId == finding.id })

        var artifactPayload: [String: String] = [
            "artifact_id": "review-finding-\(payload.jobId)-\(payload.taskId)-\(finding.id)",
            "title": "\(severityLabel(finding.severity)) \(domainLabel(for: finding)) · \(displayName(for: finding.filePath))",
            "detail": markdownCard(
                finding: finding,
                patch: patch,
                eventTitle: "Finding verificato",
                eventDetail: "Rilevato durante la review in chat."
            ),
            "finding_id": finding.id,
            "finding_status": finding.status.rawValue,
            "finding_severity": finding.severity.rawValue,
            "finding_file": finding.filePath,
        ]

        if let patch {
            artifactPayload["patch_status"] = patch.status.rawValue
            artifactPayload["patch_validation"] = patch.validationStatus.rawValue
        }
        return artifactPayload
    }

    static func reviewPanelMessage(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        eventTitle: String,
        eventDetail: String? = nil
    ) -> ReviewPanelMessage? {
        guard let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
            return nil
        }
        let patch = snapshot.patches.first(where: { $0.findingId == findingId })
        let content = markdownCard(
            finding: finding,
            patch: patch,
            eventTitle: eventTitle,
            eventDetail: eventDetail
        )
        return ReviewPanelMessage(
            role: .system,
            kind: .findingMutation,
            content: content,
            presentation: ReviewPanelMessagePresentation(
                sections: sections(
                    finding: finding,
                    patch: patch,
                    eventTitle: eventTitle,
                    eventDetail: eventDetail
                )
            )
        )
    }

    private static func sections(
        finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?,
        eventTitle: String,
        eventDetail: String?
    ) -> [ReviewPanelChatStructuredSection] {
        var sections: [ReviewPanelChatStructuredSection] = [
            ReviewPanelChatStructuredSection(
                id: "finding-metadata-\(finding.id)",
                title: eventTitle,
                lines: metadataLines(for: finding, patch: patch),
                style: .metadata,
                isInitiallyExpanded: true
            ),
            ReviewPanelChatStructuredSection(
                id: "finding-summary-\(finding.id)",
                title: "Finding",
                lines: summaryLines(for: finding, eventDetail: eventDetail),
                style: .findings,
                isInitiallyExpanded: true
            ),
        ]

        if let verification = finding.verificationReport,
           verification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "finding-verification-\(finding.id)",
                    title: "Verification",
                    lines: [verification],
                    style: .prose,
                    isInitiallyExpanded: true
                )
            )
        }

        if let patch {
            sections.append(
                ReviewPanelChatStructuredSection(
                    id: "finding-patch-\(finding.id)",
                    title: "Patch",
                    lines: patchMetadataLines(for: patch),
                    style: .metadata,
                    isInitiallyExpanded: true
                )
            )
            let diffLines = diffPreviewLines(for: patch)
            if !diffLines.isEmpty {
                sections.append(
                    ReviewPanelChatStructuredSection(
                        id: "finding-patch-preview-\(finding.id)",
                        title: "Patch Preview",
                        lines: diffLines,
                        style: .log,
                        isInitiallyExpanded: false
                    )
                )
            }
        }

        return sections
    }

    private static func markdownCard(
        finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?,
        eventTitle: String,
        eventDetail: String?
    ) -> String {
        var lines: [String] = [
            "### \(eventTitle)",
            "- severity: \(finding.severity.rawValue)",
            "- domain: \(domainLabel(for: finding))",
            "- status: \(finding.status.rawValue)",
            "- file: \(finding.filePath)\(lineSuffix(for: finding.lineNumber))",
        ]

        if let eventDetail,
           eventDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("- note: \(eventDetail)")
        }

        lines += [
            "",
            "#### Summary",
            finding.message,
        ]

        if let suggestedFix = finding.suggestedFix,
           suggestedFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines += ["", "#### Suggested Fix", suggestedFix]
        }

        if let verification = finding.verificationReport,
           verification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines += ["", "#### Verification", verification]
        }

        if let patch {
            lines += [
                "",
                "#### Patch",
                "- status: \(patch.status.rawValue)",
                "- validation: \(patch.validationStatus.rawValue)",
                "- files: \(patch.touchedFiles.joined(separator: ", "))",
                "- rollback: \(patch.rollbackRef == nil ? "not available" : "available")",
            ]
            if let summary = patch.validationSummary,
               summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                lines.append("- validation_summary: \(summary)")
            }
            let diffLines = diffPreviewLines(for: patch)
            if !diffLines.isEmpty {
                lines += ["", "#### Patch Preview", "```diff"] + diffLines + ["```"]
            }
        } else {
            lines += [
                "",
                "#### Patch",
                "Patch non ancora preparata. Dal panel puoi aprire la preview e applicare il fix dopo la review.",
            ]
        }

        return lines.joined(separator: "\n")
    }

    private static func metadataLines(
        for finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?
    ) -> [String] {
        var lines = [
            "id: \(finding.id)",
            "severity: \(finding.severity.rawValue)",
            "domain: \(domainLabel(for: finding))",
            "status: \(finding.status.rawValue)",
            "file: \(finding.filePath)\(lineSuffix(for: finding.lineNumber))",
        ]
        if let confidence = finding.confidence {
            lines.append("confidence: \(String(format: "%.2f", confidence))")
        }
        lines.append("patch_available: \(patch == nil ? "false" : "true")")
        return lines
    }

    private static func summaryLines(
        for finding: CodeReviewFinding,
        eventDetail: String?
    ) -> [String] {
        var lines = [finding.message]
        if let eventDetail,
           eventDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append(eventDetail)
        }
        if let suggestedFix = finding.suggestedFix,
           suggestedFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("Suggested fix: \(suggestedFix)")
        }
        return lines
    }

    private static func patchMetadataLines(for patch: ReviewPatchArtifact) -> [String] {
        var lines = [
            "patch_id: \(patch.id)",
            "status: \(patch.status.rawValue)",
            "validation: \(patch.validationStatus.rawValue)",
            "risk_score: \(String(format: "%.2f", patch.riskScore))",
            "touched_files: \(patch.touchedFiles.count)",
        ]
        if let summary = patch.validationSummary,
           summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("validation_summary: \(summary)")
        }
        if let message = patch.applyMessage,
           message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("apply_message: \(message)")
        }
        return lines
    }

    private static func diffPreviewLines(for patch: ReviewPatchArtifact) -> [String] {
        patch.diffPreview
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { $0.isEmpty == false }
            .prefix(16)
            .map { $0 }
    }

    private static func domainLabel(for finding: CodeReviewFinding) -> String {
        switch finding.origin {
        case .securityAuditor:
            return "security"
        case .bugHunter:
            return "bug"
        case .reviewer, .auditTool:
            return "review"
        }
    }

    private static func severityLabel(_ severity: FindingSeverity) -> String {
        severity.rawValue.uppercased()
    }

    private static func displayName(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func lineSuffix(for line: Int?) -> String {
        guard let line else { return "" }
        return ":\(line)"
    }

    private static func syntheticFinding(from payload: ReviewFindingPayload) -> CodeReviewFinding {
        CodeReviewFinding(
            id: payload.finding.findingId,
            severity: payload.finding.severity,
            category: .other,
            origin: .reviewer,
            filePath: payload.finding.file,
            lineNumber: payload.finding.line,
            message: payload.finding.message,
            suggestedFix: payload.finding.suggestedFix,
            confidence: 0.80,
            evidence: payload.finding.message,
            sourceTool: "pipeline",
            status: payload.finding.status,
            verificationReport: "Captured from pipeline review finding event",
            verifiedAt: Date(),
            verificationMethod: "pipeline_event"
        )
    }
}
