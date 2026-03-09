import Foundation

public struct VerifiedFindingIdentityMatch: Sendable, Equatable {
    public let existingFindingId: String
    public let isExactDuplicate: Bool
    public let score: Double
}

public enum FindingIdentityService {
    struct PreparedFindingIdentity: Sendable {
        let findingId: String
        let domain: VerifiedFindingDomain
        let fingerprint: String
        let normalizedFilePath: String
        let normalizedCategory: String
        let normalizedTitle: String
        let normalizedSummary: String
        let lineStart: Int?

        init(finding: VerifiedFinding) {
            self.findingId = finding.id
            self.domain = finding.domain
            self.fingerprint = finding.findingFingerprint
            self.normalizedFilePath = FindingIdentityService.normalize(finding.filePath)
            self.normalizedCategory = FindingIdentityService.normalize(finding.category)
            self.normalizedTitle = FindingIdentityService.normalize(finding.title)
            self.normalizedSummary = FindingIdentityService.normalize(finding.summary)
            self.lineStart = finding.lineStart
        }
    }

    struct IdentityIndex {
        private var exactFingerprintToFindingId: [String: String] = [:]
        private var identitiesById: [String: PreparedFindingIdentity] = [:]
        private var identitiesByFilePath: [String: Set<String>] = [:]
        private var identitiesByTitle: [String: Set<String>] = [:]
        private var identitiesBySummary: [String: Set<String>] = [:]

        mutating func insert(_ identity: PreparedFindingIdentity) {
            exactFingerprintToFindingId[FindingIdentityService.exactFingerprintKey(for: identity)] = identity.findingId
            identitiesById[identity.findingId] = identity
            let filePathKey = FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedFilePath)
            let titleKey = FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedTitle)
            let summaryKey = FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedSummary)
            identitiesByFilePath[filePathKey, default: []].insert(identity.findingId)
            identitiesByTitle[titleKey, default: []].insert(identity.findingId)
            identitiesBySummary[summaryKey, default: []].insert(identity.findingId)
        }

        func exactDuplicateId(for identity: PreparedFindingIdentity) -> String? {
            exactFingerprintToFindingId[FindingIdentityService.exactFingerprintKey(for: identity)]
        }

        func candidates(for identity: PreparedFindingIdentity) -> [PreparedFindingIdentity] {
            let keys = [
                FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedFilePath),
                FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedTitle),
                FindingIdentityService.bucketKey(domain: identity.domain, value: identity.normalizedSummary),
            ]
            let candidateIds = keys.reduce(into: Set<String>()) { partialResult, key in
                partialResult.formUnion(identitiesByFilePath[key] ?? [])
                partialResult.formUnion(identitiesByTitle[key] ?? [])
                partialResult.formUnion(identitiesBySummary[key] ?? [])
            }
            return candidateIds.compactMap { identitiesById[$0] }
        }
    }

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
        let candidateIdentity = prepare(candidate)
        var index = IdentityIndex()
        for finding in existing where finding.domain == candidate.domain {
            index.insert(prepare(finding))
        }
        return findDuplicate(
            candidateIdentity: candidateIdentity,
            existingIndex: index,
            minimumScore: minimumScore
        )
    }

    static func prepare(_ finding: VerifiedFinding) -> PreparedFindingIdentity {
        PreparedFindingIdentity(finding: finding)
    }

    static func findDuplicate(
        candidateIdentity: PreparedFindingIdentity,
        existingIndex: IdentityIndex,
        minimumScore: Double = 0.75
    ) -> VerifiedFindingIdentityMatch? {
        if let existingFindingId = existingIndex.exactDuplicateId(for: candidateIdentity) {
            return VerifiedFindingIdentityMatch(
                existingFindingId: existingFindingId,
                isExactDuplicate: true,
                score: 1.0
            )
        }

        var bestMatch: VerifiedFindingIdentityMatch?
        for existingIdentity in existingIndex.candidates(for: candidateIdentity) {
            let score = similarityScore(lhs: candidateIdentity, rhs: existingIdentity)
            guard score >= minimumScore else { continue }
            let match = VerifiedFindingIdentityMatch(
                existingFindingId: existingIdentity.findingId,
                isExactDuplicate: existingIdentity.fingerprint == candidateIdentity.fingerprint,
                score: score
            )
            if shouldReplaceBestMatch(match, current: bestMatch) {
                bestMatch = match
            }
        }
        return bestMatch
    }

    private static func shouldReplaceBestMatch(
        _ candidate: VerifiedFindingIdentityMatch,
        current: VerifiedFindingIdentityMatch?
    ) -> Bool {
        guard let current else { return true }
        if candidate.isExactDuplicate != current.isExactDuplicate {
            return candidate.isExactDuplicate && !current.isExactDuplicate
        }
        return candidate.score > current.score
    }

    private static func similarityScore(
        lhs: PreparedFindingIdentity,
        rhs: PreparedFindingIdentity
    ) -> Double {
        var score = 0.0
        if lhs.normalizedFilePath == rhs.normalizedFilePath { score += 0.35 }
        if lhs.normalizedCategory == rhs.normalizedCategory { score += 0.20 }
        if compatibleLines(lhs.lineStart, rhs.lineStart) { score += 0.15 }
        if lhs.normalizedTitle == rhs.normalizedTitle { score += 0.15 }
        if lhs.normalizedSummary == rhs.normalizedSummary { score += 0.15 }
        return score
    }

    private static func compatibleLines(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs - rhs) <= 3
    }

    private static func bucketKey(domain: VerifiedFindingDomain, value: String) -> String {
        "\(domain.rawValue)|\(value)"
    }

    private static func exactFingerprintKey(for identity: PreparedFindingIdentity) -> String {
        bucketKey(domain: identity.domain, value: identity.fingerprint)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
