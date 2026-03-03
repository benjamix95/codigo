import Foundation

extension DebugStore {
    // MARK: - Hypothesis Management

    @discardableResult
    func addHypothesis(
        id: UUID? = nil,
        title: String,
        description: String,
        status: DebugHypothesis.HypothesisStatus = .proposed,
        evidence: String? = nil
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
                    evidence: hypotheses[idx].evidence,
                    createdAt: hypotheses[idx].createdAt
                )
            }
            if let evidence, !evidence.isEmpty {
                hypotheses[idx].evidence.append(evidence)
            }
            return resolvedId
        }

        var h = DebugHypothesis(id: resolvedId, title: title, description: description)
        h.status = status
        if let evidence, !evidence.isEmpty {
            h.evidence.append(evidence)
        }
        hypotheses.append(h)
        return h.id
    }

    @discardableResult
    func updateHypothesis(id: UUID, status: DebugHypothesis.HypothesisStatus, evidence: String? = nil) -> Bool {
        guard let idx = hypotheses.firstIndex(where: { $0.id == id }) else { return false }
        hypotheses[idx].status = status
        if let ev = evidence, !ev.isEmpty {
            hypotheses[idx].evidence.append(ev)
        }
        return true
    }
}
