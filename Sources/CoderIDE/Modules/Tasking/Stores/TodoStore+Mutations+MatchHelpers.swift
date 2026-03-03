import Foundation

extension TodoStore {
    func canonicalKey(for title: String) -> String {
        title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
    }

    func canonicalTokens(for key: String) -> Set<String> {
        Set(
            key
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    func isLikelyCanonicalMatch(titleKey: String, canonicalKey: String) -> Bool {
        let titleTokens = canonicalTokens(for: titleKey)
        let canonicalTokens = canonicalTokens(for: canonicalKey)

        guard titleTokens.count >= 2 && canonicalTokens.count >= 2 else {
            return false
        }
        if canonicalKey.count >= 12 && titleKey.count >= 12 {
            if canonicalKey.contains(titleKey) || titleKey.contains(canonicalKey) {
                return true
            }
        }
        let overlap = Double(titleTokens.intersection(canonicalTokens).count)
        guard overlap > 0 else { return false }
        let shortSetSize = min(titleTokens.count, canonicalTokens.count)
        guard shortSetSize > 0 else { return false }
        let overlapRatio = overlap / Double(shortSetSize)
        return overlapRatio >= 0.7 && overlap >= 2
    }
}
