import Foundation

public struct VerifiedFindingIdentityMatch: Sendable, Equatable {
    public let existingFindingId: String
    public let isExactDuplicate: Bool
    public let score: Double
}

public enum FindingIdentityService {
    public static func fingerprint(
        domain: VerifiedFindingDomain,
        filePath: String,
        category: String,
        title: String,
        lineStart: Int?,
        summary: String
    ) -> String {
        let normalized = [
            domain.rawValue,
            normalize(filePath),
            normalize(category),
            normalize(title),
            String(lineStart ?? 0),
            normalize(summary),
        ].joined(separator: "|")
        return normalized
    }

    public static func findDuplicate(
        candidate: VerifiedFinding,
        existing: [VerifiedFinding],
        minimumScore: Double = 0.75
    ) -> VerifiedFindingIdentityMatch? {
        existing
            .filter { $0.domain == candidate.domain }
            .compactMap { finding -> VerifiedFindingIdentityMatch? in
                let score = similarityScore(lhs: candidate, rhs: finding)
                guard score >= minimumScore else { return nil }
                return VerifiedFindingIdentityMatch(
                    existingFindingId: finding.id,
                    isExactDuplicate: finding.findingFingerprint == candidate.findingFingerprint,
                    score: score
                )
            }
            .sorted { lhs, rhs in
                if lhs.isExactDuplicate != rhs.isExactDuplicate {
                    return lhs.isExactDuplicate && !rhs.isExactDuplicate
                }
                return lhs.score > rhs.score
            }
            .first
    }

    private static func similarityScore(lhs: VerifiedFinding, rhs: VerifiedFinding) -> Double {
        var score = 0.0
        if normalize(lhs.filePath) == normalize(rhs.filePath) { score += 0.35 }
        if lhs.category.caseInsensitiveCompare(rhs.category) == .orderedSame { score += 0.20 }
        if compatibleLines(lhs.lineStart, rhs.lineStart) { score += 0.15 }
        if normalize(lhs.title) == normalize(rhs.title) { score += 0.15 }
        if normalize(lhs.summary) == normalize(rhs.summary) { score += 0.15 }
        return score
    }

    private static func compatibleLines(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs - rhs) <= 3
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
