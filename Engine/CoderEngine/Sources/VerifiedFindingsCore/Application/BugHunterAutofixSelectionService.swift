import Foundation

public enum BugHunterAutofixSelectionService {
    public static func selectFindingId(
        from resolvedState: VerifiedFindingsResolvedState,
        minimumConfidence: Double = 0.9
    ) -> String? {
        resolvedState.recovered.envelope.canonicalSnapshot.findings.values
            .filter { finding in
                finding.domain == .bug
                    && finding.status == .verified
                    && finding.confidence >= minimumConfidence
                    && finding.mergedIntoFindingId == nil
            }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.confidence > rhs.confidence
            }
            .first?.id
    }
}
