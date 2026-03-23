import Foundation

extension DebugStore {
    // MARK: - Hypothesis Management

    @discardableResult
    func addHypothesis(
        id: UUID? = nil,
        title: String,
        description: String,
        status: DebugHypothesis.HypothesisStatus = .proposed,
        evidence: String? = nil,
        confidence: Int = 50,
        rootCauseType: String = "",
        relatedFiles: [String] = [],
        relatedTests: [String] = []
    ) -> UUID {
        let resolvedId = id ?? UUID()
        if let idx = hypotheses.firstIndex(where: { $0.id == resolvedId }) {
            hypotheses[idx].status = status
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hypotheses[idx] = DebugHypothesis(
                    id: resolvedId,
                    title: title,
                    description: description,
                    status: status,
                    confidence: confidence,
                    rootCauseType: rootCauseType,
                    relatedFiles: relatedFiles,
                    relatedTests: relatedTests,
                    evidence: hypotheses[idx].evidence,
                    createdAt: hypotheses[idx].createdAt
                )
            } else {
                hypotheses[idx].confidence = confidence
                if !rootCauseType.isEmpty { hypotheses[idx].rootCauseType = rootCauseType }
                if !relatedFiles.isEmpty { hypotheses[idx].relatedFiles = relatedFiles }
                if !relatedTests.isEmpty { hypotheses[idx].relatedTests = relatedTests }
            }
            if let evidence, !evidence.isEmpty {
                hypotheses[idx].evidence.append(evidence)
            }
            return resolvedId
        }

        var h = DebugHypothesis(
            id: resolvedId,
            title: title,
            description: description,
            confidence: confidence,
            rootCauseType: rootCauseType,
            relatedFiles: relatedFiles,
            relatedTests: relatedTests
        )
        h.status = status
        if let evidence, !evidence.isEmpty {
            h.evidence.append(evidence)
        }
        hypotheses.append(h)
        return h.id
    }

    @discardableResult
    func updateHypothesis(
        id: UUID,
        status: DebugHypothesis.HypothesisStatus,
        evidence: String? = nil,
        confidence: Int? = nil,
        rootCauseType: String? = nil,
        relatedFiles: [String] = [],
        relatedTests: [String] = []
    ) -> Bool {
        guard let idx = hypotheses.firstIndex(where: { $0.id == id }) else { return false }
        hypotheses[idx].status = status
        if let confidence {
            hypotheses[idx].confidence = min(max(confidence, 0), 100)
        }
        if let rootCauseType, !rootCauseType.isEmpty {
            hypotheses[idx].rootCauseType = rootCauseType
        }
        if !relatedFiles.isEmpty {
            hypotheses[idx].relatedFiles = relatedFiles
        }
        if !relatedTests.isEmpty {
            hypotheses[idx].relatedTests = relatedTests
        }
        if let ev = evidence, !ev.isEmpty {
            hypotheses[idx].evidence.append(ev)
        }
        return true
    }
}
