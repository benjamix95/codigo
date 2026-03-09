import Foundation

extension CodeReviewFinding {
    public static func fromRawTask(
        id: String,
        description: String,
        files: [String],
        severity severityStr: String,
        category categoryStr: String? = nil,
        origin: FindingOrigin = .reviewer,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        confidence: Double? = nil,
        evidence: String? = nil,
        sourceTool: String? = nil,
        blocking: Bool? = nil
    ) -> CodeReviewFinding {
        let severity: FindingSeverity
        switch severityStr.lowercased() {
        case "critical", "error", "high":
            severity = .critical
        case "warning", "medium":
            severity = .warning
        case "suggestion", "low", "info":
            severity = .suggestion
        default:
            severity = .warning
        }

        let category: FindingCategory
        if let raw = categoryStr?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            category = FindingCategory.fromStoredValue(raw)
        } else {
            category = inferCategory(from: description)
        }

        return CodeReviewFinding(
            id: id,
            severity: severity,
            category: category,
            origin: origin,
            filePath: filePath ?? files.first ?? "unknown",
            lineNumber: lineNumber,
            message: description,
            confidence: confidence,
            evidence: evidence,
            sourceTool: sourceTool,
            blocking: blocking
        )
    }

    public static func fromCandidate(_ candidate: ReviewCandidate) -> CodeReviewFinding {
        CodeReviewFinding(
            id: candidate.id,
            severity: candidate.severity,
            category: candidate.category,
            origin: candidate.origin,
            filePath: candidate.filePath,
            lineNumber: candidate.lineNumber,
            endLineNumber: candidate.endLineNumber,
            message: candidate.message,
            suggestedFix: candidate.reproOrReasoning,
            expectedInvariant: candidate.expectedInvariant,
            reproOrReasoning: candidate.reproOrReasoning,
            confidence: candidate.confidence,
            evidence: candidate.evidence,
            sourceTool: candidate.sourceTool,
            blocking: candidate.severity == .critical,
            verificationReport: candidate.verificationReport,
            verifiedAt: candidate.verifiedAt ?? Date(),
            verificationMethod: candidate.verificationMethod
        )
    }

    private static func inferCategory(from description: String) -> FindingCategory {
        let lower = description.lowercased()
        if lower.contains("security") || lower.contains("vulnerability") || lower.contains("injection") {
            return .security
        }
        if lower.contains("race") || lower.contains("deadlock") || lower.contains("thread") || lower.contains("concurrency") {
            return .concurrency
        }
        if lower.contains("regression") || lower.contains("crash") || lower.contains("fatal") || lower.contains("force unwrap") {
            return .regression
        }
        if lower.contains("performance") || lower.contains("slow") || lower.contains("o(n") {
            return .performance
        }
        if lower.contains("test") || lower.contains("coverage") {
            return .tests
        }
        if lower.contains("style") || lower.contains("naming") || lower.contains("format")
            || lower.contains("architecture") || lower.contains("coupling") || lower.contains("refactor")
            || lower.contains("doc") || lower.contains("comment") {
            return .maintainability
        }
        return .correctness
    }

    public func toPayload() -> [String: String] {
        var payload: [String: String] = [
            "id": id,
            "severity": severity.rawValue,
            "category": category.rawValue,
            "origin": origin.rawValue,
            "file_path": filePath,
            "message": message,
            "status": status.rawValue,
            "blocking": blocking ? "true" : "false",
        ]
        if let ln = lineNumber { payload["line_number"] = String(ln) }
        if let eln = endLineNumber { payload["end_line_number"] = String(eln) }
        if let fix = suggestedFix { payload["suggested_fix"] = fix }
        if let expectedInvariant, !expectedInvariant.isEmpty {
            payload["expected_invariant"] = expectedInvariant
        }
        if let reproOrReasoning, !reproOrReasoning.isEmpty {
            payload["repro_or_reasoning"] = reproOrReasoning
        }
        if let confidence { payload["confidence"] = String(format: "%.2f", confidence) }
        if let evidence, !evidence.isEmpty { payload["evidence"] = evidence }
        if let sourceTool, !sourceTool.isEmpty { payload["source_tool"] = sourceTool }
        if let verificationReport, !verificationReport.isEmpty {
            payload["verification_report"] = verificationReport
        }
        if let verificationMethod, !verificationMethod.isEmpty {
            payload["verification_method"] = verificationMethod
        }
        if let verifiedAt {
            payload["verified_at"] = ISO8601DateFormatter().string(from: verifiedAt)
        }
        if let falsePositiveReason, !falsePositiveReason.isEmpty {
            payload["false_positive_reason"] = falsePositiveReason
        }
        if let patchArtifactId, !patchArtifactId.isEmpty {
            payload["patch_artifact_id"] = patchArtifactId
        }
        if !comments.isEmpty { payload["comment_count"] = String(comments.count) }
        return payload
    }
}

extension FindingCategory {
    public static func fromStoredValue(_ raw: String) -> FindingCategory {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "correctness", "bug":
            return .correctness
        case "regression":
            return .regression
        case "concurrency":
            return .concurrency
        case "security":
            return .security
        case "performance":
            return .performance
        case "tests", "testing":
            return .tests
        case "maintainability", "style", "architecture", "documentation":
            return .maintainability
        default:
            return .other
        }
    }
}
