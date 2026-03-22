import Foundation

extension UnifiedToolRuntime {
    func executeDebugHypothesize(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let title = (call.args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (call.args["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let action = (call.args["action"] ?? "propose").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hypothesisId = (call.args["hypothesis_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedStatus = (call.args["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let evidence = call.args["evidence"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = Int(call.args["confidence"] ?? "") ?? -1
        let rootCauseType = (call.args["root_cause_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let relatedFiles = (call.args["related_files"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let relatedTests = (call.args["related_tests"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "propose":
            return await proposeHypothesis(
                title: title, description: description, requestedStatus: requestedStatus,
                evidence: evidence, confidence: confidence, rootCauseType: rootCauseType,
                relatedFiles: relatedFiles, relatedTests: relatedTests, ms: ms
            )
        case "update":
            return await updateHypothesis(
                hypothesisId: hypothesisId, requestedStatus: requestedStatus,
                evidence: evidence, confidence: confidence, rootCauseType: rootCauseType,
                relatedFiles: relatedFiles, relatedTests: relatedTests, ms: ms
            )
        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use propose or update."], durationMs: ms)
        }
    }

    // MARK: - Propose

    private func proposeHypothesis(
        title: String, description: String, requestedStatus: String,
        evidence: String?, confidence: Int, rootCauseType: String,
        relatedFiles: [String], relatedTests: [String], ms: Int
    ) async -> ToolResult {
        guard !title.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "title is required for propose action"], durationMs: ms)
        }

        let newHypothesisId = UUID().uuidString
        let normalizedStatus = normalizeHypothesisStatus(requestedStatus, fallback: "proposed")
        let clampedConfidence = confidence >= 0 ? min(max(confidence, 0), 100) : 50

        debugHypotheses[newHypothesisId] = DebugHypothesis(
            title: title,
            description: description,
            status: normalizedStatus,
            confidence: clampedConfidence,
            rootCauseType: rootCauseType,
            relatedFiles: relatedFiles,
            relatedTests: relatedTests,
            evidence: evidence != nil ? [evidence!] : [],
            createdAt: Date()
        )

        var logDetail = description
        if !rootCauseType.isEmpty { logDetail += "\nType: \(rootCauseType)" }
        if !relatedFiles.isEmpty { logDetail += "\nFiles: \(relatedFiles.joined(separator: ", "))" }

        await debugLogServer.log(
            severity: "info",
            source: "hypothesis",
            message: "Hypothesis \(newHypothesisId.prefix(8)) proposed: \(title) [confidence: \(clampedConfidence)%]",
            detail: logDetail,
            category: "debug"
        )
        await debugLogServer.persistHypothesis(
            id: newHypothesisId, title: title, status: normalizedStatus,
            confidence: clampedConfidence, description: description,
            rootCauseType: rootCauseType, relatedFiles: relatedFiles,
            evidence: evidence != nil ? [evidence!] : []
        )

        var output = "Proposed hypothesis \(newHypothesisId.prefix(8)): \(title)\n"
        output += "  Status: \(normalizedStatus)\n"
        output += "  Confidence: \(clampedConfidence)%\n"
        if !rootCauseType.isEmpty { output += "  Root cause type: \(rootCauseType)\n" }
        if !relatedFiles.isEmpty { output += "  Related files: \(relatedFiles.joined(separator: ", "))\n" }
        if !relatedTests.isEmpty { output += "  Related tests: \(relatedTests.joined(separator: ", "))\n" }

        return ToolResult(ok: true, payload: [
            "title": "debug_hypothesize",
            "detail": "Hypothesis proposed: \(title) [\(clampedConfidence)%]",
            "output": output,
            "action": "propose",
            "hypothesis_id": newHypothesisId,
            "hypothesis_title": title,
            "description": description,
            "hypothesis_status": normalizedStatus,
            "confidence": "\(clampedConfidence)",
            "root_cause_type": rootCauseType,
            "related_files": relatedFiles.joined(separator: ","),
            "evidence": evidence ?? ""
        ], durationMs: ms)
    }

    // MARK: - Update

    private func updateHypothesis(
        hypothesisId: String, requestedStatus: String,
        evidence: String?, confidence: Int, rootCauseType: String,
        relatedFiles: [String], relatedTests: [String], ms: Int
    ) async -> ToolResult {
        guard !hypothesisId.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "hypothesis_id is required for update"], durationMs: ms)
        }
        let resolvedHypothesisId: String
        switch resolveHypothesisLookup(hypothesisId) {
        case .resolved(let id):
            resolvedHypothesisId = id
        case .ambiguous(let prefixes):
            return ToolResult(
                ok: false,
                payload: ["detail": "Ambiguous hypothesis_id prefix '\(hypothesisId)'. Matches: \(prefixes.joined(separator: ", "))"],
                durationMs: ms
            )
        case .notFound:
            return ToolResult(ok: false, payload: ["detail": "Unknown hypothesis_id: \(hypothesisId)"], durationMs: ms)
        }
        guard var existing = debugHypotheses[resolvedHypothesisId] else {
            return ToolResult(ok: false, payload: ["detail": "Unknown hypothesis_id: \(hypothesisId)"], durationMs: ms)
        }

        let nextStatus = normalizeHypothesisStatus(requestedStatus, fallback: existing.status)
        existing.status = nextStatus
        if confidence >= 0 { existing.confidence = min(max(confidence, 0), 100) }
        if !rootCauseType.isEmpty { existing.rootCauseType = rootCauseType }
        if !relatedFiles.isEmpty { existing.relatedFiles = relatedFiles }
        if !relatedTests.isEmpty { existing.relatedTests = relatedTests }
        if let evidence { existing.evidence.append(evidence) }
        debugHypotheses[resolvedHypothesisId] = existing

        await debugLogServer.log(
            severity: "info",
            source: "hypothesis",
            message: "Hypothesis \(resolvedHypothesisId.prefix(8)) updated to \(nextStatus) [confidence: \(existing.confidence)%]",
            detail: evidence,
            category: "debug"
        )
        await debugLogServer.persistHypothesis(
            id: resolvedHypothesisId, title: existing.title, status: nextStatus,
            confidence: existing.confidence, description: existing.description,
            rootCauseType: existing.rootCauseType, relatedFiles: existing.relatedFiles,
            evidence: existing.evidence
        )

        var output = "Updated hypothesis \(resolvedHypothesisId.prefix(8)) -> \(nextStatus)\n"
        output += "  Title: \(existing.title)\n"
        output += "  Confidence: \(existing.confidence)%\n"
        if !existing.rootCauseType.isEmpty { output += "  Root cause type: \(existing.rootCauseType)\n" }
        if !existing.relatedFiles.isEmpty { output += "  Related files: \(existing.relatedFiles.joined(separator: ", "))\n" }
        if existing.evidence.count > 1 { output += "  Evidence entries: \(existing.evidence.count)\n" }

        return ToolResult(ok: true, payload: [
            "title": "debug_hypothesize",
            "detail": "Hypothesis updated to \(nextStatus) [\(existing.confidence)%]",
            "output": output,
            "action": "update",
            "hypothesis_id": resolvedHypothesisId,
            "hypothesis_title": existing.title,
            "description": existing.description,
            "hypothesis_status": nextStatus,
            "confidence": "\(existing.confidence)",
            "root_cause_type": existing.rootCauseType,
            "related_files": existing.relatedFiles.joined(separator: ","),
            "evidence": evidence ?? ""
        ], durationMs: ms)
    }
}
